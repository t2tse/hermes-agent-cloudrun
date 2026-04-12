FROM python:3.11-slim

# System dependencies for Hermes Agent
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    nodejs \
    npm \
    ripgrep \
    ffmpeg \
    gcc \
    python3-dev \
    libffi-dev \
    procps \
    curl \
    git \
    jq \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
RUN pip install --no-cache-dir uv

# Clone and install Hermes Agent from source
RUN git clone --branch v2026.4.8 --depth 1 https://github.com/nousresearch/hermes-agent.git /tmp/hermes-agent \
    && cd /tmp/hermes-agent \
    && uv pip install --system -e ".[messaging,cron,cli,pty,mcp,honcho]" \
    && rm -rf /tmp/hermes-agent/.git

# Install google-auth for Vertex AI ADC proxy
RUN uv pip install --system google-auth

# Install Playwright Chromium for browser automation
RUN playwright install --with-deps chromium || true

# Copy Vertex AI proxy (replaces LiteLLM -- handles ADC token injection)
COPY scripts/vertex_ai_proxy.py /opt/hermes/vertex_ai_proxy.py

# Copy config template and entrypoint
COPY hermes-config.yaml.template /opt/hermes/config.yaml.template
COPY scripts/entrypoint.sh /opt/hermes/entrypoint.sh
RUN chmod +x /opt/hermes/entrypoint.sh

# Data volume mount point
RUN mkdir -p /opt/data
VOLUME /opt/data

ENV HERMES_HOME=/opt/data

ENTRYPOINT ["/opt/hermes/entrypoint.sh"]
