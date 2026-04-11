#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"

# Create required directories
for dir in cron sessions logs hooks memories skills skins plans workspace home; do
  mkdir -p "$HERMES_HOME/$dir"
done

# ── Render config.yaml from template ────────────────────────────────────────
export HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-gemini-2.5-pro-preview-06-05}"

envsubst '$HERMES_DEFAULT_MODEL' \
  < /opt/hermes/config.yaml.template \
  > "$HERMES_HOME/config.yaml"

# ── Render .env file ────────────────────────────────────────────────────────
# No API keys needed -- Vertex AI proxy handles auth via ADC/Workload Identity
cat > "$HERMES_HOME/.env" << 'EOF'
# Vertex AI proxy handles authentication -- no API keys required
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
