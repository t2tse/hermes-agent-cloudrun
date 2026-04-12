#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"

# Create required directories
for dir in cron sessions logs hooks memories skills skins plans workspace home; do
  mkdir -p "$HERMES_HOME/$dir"
done

# ── Render config.yaml from template (only on first run) ────────────────────
export HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-gemini-2.5-pro-preview-06-05}"

if [ ! -f "$HERMES_HOME/config.yaml" ]; then
  echo "[entrypoint] Rendering config.yaml from template..."
  envsubst '$HERMES_DEFAULT_MODEL' \
    < /opt/hermes/config.yaml.template \
    > "$HERMES_HOME/config.yaml"
else
  echo "[entrypoint] Using existing config.yaml"
fi

# ── Render .env file ────────────────────────────────────────────────────────
# OPENAI_API_KEY is set to a placeholder so Hermes skips the first-run setup
# wizard. The actual auth is handled by the Vertex AI proxy via ADC.
cat > "$HERMES_HOME/.env" << 'EOF'
OPENAI_API_KEY=not-needed-proxy-handles-auth
EOF

# ── Start Vertex AI proxy (background) ──────────────────────────────────────
echo "[entrypoint] Starting Vertex AI proxy on :${VERTEX_PROXY_PORT:-8081}..."
python3 /opt/hermes/vertex_ai_proxy.py &
PROXY_PID=$!

# Wait for proxy to be ready
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:${VERTEX_PROXY_PORT:-8081}/health >/dev/null 2>&1; then
    echo "[entrypoint] Vertex AI proxy ready"
    break
  fi
  sleep 1
done

# ── Start Hermes Agent ──────────────────────────────────────────────────────
echo "[entrypoint] Starting Hermes Agent..."
exec hermes gateway run "$@"
