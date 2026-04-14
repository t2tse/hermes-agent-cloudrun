#!/usr/bin/env python3
"""Lightweight Vertex AI OpenAI-compatible proxy.

Replaces LiteLLM. Runs as a background process inside the Hermes pod.
Uses Application Default Credentials (ADC) via Workload Identity to
authenticate with Vertex AI, and exposes an OpenAI-compatible API on
localhost:8081 that Hermes can use as a custom provider.

Supports both streaming (SSE) and non-streaming chat completions.
Token refresh is handled automatically by google-auth.
"""

import json
import logging
import os
import sys
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

import httpx
import google.auth
import google.auth.transport.requests

logging.basicConfig(level=logging.INFO, format="[vertex-proxy] %(message)s", stream=sys.stdout)
# Redirect httpx logs to stdout too (GKE treats stderr as severity=ERROR)
logging.getLogger("httpx").handlers = logging.getLogger().handlers
log = logging.getLogger(__name__)

PROJECT = os.environ.get("VERTEX_PROJECT", "")
LOCATION = os.environ.get("VERTEX_LOCATION", "us-central1")
LISTEN_PORT = int(os.environ.get("VERTEX_PROXY_PORT", "8081"))

# Global endpoint uses a different hostname pattern
if LOCATION == "global":
    VERTEX_BASE = f"https://aiplatform.googleapis.com/v1beta1/projects/{PROJECT}/locations/global/endpoints/openapi"
else:
    VERTEX_BASE = f"https://{LOCATION}-aiplatform.googleapis.com/v1beta1/projects/{PROJECT}/locations/{LOCATION}/endpoints/openapi"

# Model alias map: short name -> Vertex AI model ID
MODEL_ALIASES = {}

# Maximum request body size (10 MB) to prevent OOM from oversized payloads
MAX_BODY_SIZE = 10 * 1024 * 1024

# Response headers safe to forward (allowlist instead of blocklist)
_SAFE_RESPONSE_HEADERS = {"content-type", "x-request-id", "x-goog-request-id"}

credentials = None
auth_request = google.auth.transport.requests.Request()
cred_lock = threading.Lock()


def get_token():
    global credentials
    with cred_lock:
        if credentials is None:
            credentials, _ = google.auth.default(
                scopes=["https://www.googleapis.com/auth/cloud-platform"]
            )
        if not credentials.valid:
            credentials.refresh(auth_request)
        return credentials.token


def _rewrite_body(body: bytes) -> bytes:
    """Resolve model aliases and add google/ prefix for Vertex AI."""
    try:
        data = json.loads(body)
        model = data.get("model", "")
        if model in MODEL_ALIASES:
            model = MODEL_ALIASES[model]
        if not model.startswith("google/"):
            model = f"google/{model}"
        data["model"] = model
        return json.dumps(data).encode()
    except (json.JSONDecodeError, KeyError):
        return body


def _target_path(request_path: str) -> str:
    """Strip /v1 prefix from the incoming path."""
    if request_path.startswith("/v1/"):
        return "/" + request_path[4:]
    return request_path


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > MAX_BODY_SIZE:
            self.send_response(413)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": {"message": f"Request body too large ({content_length} bytes, max {MAX_BODY_SIZE})", "type": "proxy_error"}}).encode())
            return
        body = self.rfile.read(content_length)
        body = _rewrite_body(body)

        # Detect if client requested streaming
        is_streaming = False
        try:
            data = json.loads(body)
            is_streaming = data.get("stream", False)
        except (json.JSONDecodeError, KeyError):
            pass

        path = _target_path(self.path)
        target_url = f"{VERTEX_BASE}{path}"
        token = get_token()

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        if is_streaming:
            self._handle_streaming(target_url, body, headers)
        else:
            self._handle_non_streaming(target_url, body, headers)

    def _handle_streaming(self, url, body, headers):
        """Forward request and stream SSE response back to client."""
        try:
            with httpx.Client(timeout=httpx.Timeout(300.0, connect=10.0)) as client:
                with client.stream("POST", url, content=body, headers=headers) as resp:
                    self.send_response(resp.status_code)
                    # Only forward safe headers; strip encoding since httpx decompresses
                    for key, val in resp.headers.items():
                        if key.lower() in ("content-type", "x-request-id"):
                            self.send_header(key, val)
                    # Override content-type for SSE
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Transfer-Encoding", "chunked")
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Connection", "keep-alive")
                    self.end_headers()

                    for chunk in resp.iter_bytes():
                        if chunk:
                            # Send as HTTP chunked encoding
                            self.wfile.write(f"{len(chunk):x}\r\n".encode())
                            self.wfile.write(chunk)
                            self.wfile.write(b"\r\n")
                            self.wfile.flush()

                    # Final chunk
                    self.wfile.write(b"0\r\n\r\n")
                    self.wfile.flush()

        except httpx.HTTPStatusError as e:
            error_body = e.response.read()
            log.error("Vertex AI stream error %d: %s", e.response.status_code, error_body.decode()[:500])
            self.send_response(e.response.status_code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(error_body)
        except Exception as e:
            log.error("Proxy stream error: %s", e)
            try:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": {"message": str(e), "type": "proxy_error"}}).encode())
            except Exception:
                pass

    def _handle_non_streaming(self, url, body, headers):
        """Forward request and return complete response."""
        try:
            resp = httpx.post(url, content=body, headers=headers, timeout=300.0)
            self.send_response(resp.status_code)
            for key, val in resp.headers.items():
                if key.lower() in _SAFE_RESPONSE_HEADERS:
                    self.send_header(key, val)
            resp_body = resp.content  # already decompressed by httpx
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)
        except Exception as e:
            log.error("Vertex AI error: %s", e)
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": {"message": str(e), "type": "proxy_error"}}).encode())

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        elif self.path in ("/v1/models", "/models"):
            models = [{"id": alias, "object": "model"} for alias in MODEL_ALIASES]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"data": models, "object": "list"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        log.debug(format, *args)


class ThreadedHTTPServer(HTTPServer):
    """Handle each request in a new thread for concurrent streaming."""
    def process_request(self, request, client_address):
        t = threading.Thread(target=self.process_request_thread, args=(request, client_address))
        t.daemon = True
        t.start()

    def process_request_thread(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        except Exception:
            self.handle_error(request, client_address)
        finally:
            self.shutdown_request(request)


def main():
    if not PROJECT:
        log.error("VERTEX_PROJECT must be set")
        sys.exit(1)

    aliases_json = os.environ.get("VERTEX_MODEL_ALIASES", "{}")
    global MODEL_ALIASES
    MODEL_ALIASES = json.loads(aliases_json)

    log.info("Starting Vertex AI proxy on :%d -> %s", LISTEN_PORT, VERTEX_BASE)
    log.info("Model aliases: %s", MODEL_ALIASES)
    log.info("Streaming support: enabled (SSE)")

    server = ThreadedHTTPServer(("127.0.0.1", LISTEN_PORT), ProxyHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
