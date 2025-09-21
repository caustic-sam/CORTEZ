# Minimal Home Assistant container (template)
# Note: This is a lightweight template. For production use, prefer the official Home Assistant images.

FROM python:3.11-slim

# Create a non-root user
RUN useradd -m -d /home/homeassistant -s /bin/bash homeassistant

WORKDIR /home/homeassistant

# Install minimal deps (example only)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy local config if provided
COPY config/ ./config/

# Ensure correct ownership
RUN chown -R homeassistant:homeassistant /home/homeassistant

USER homeassistant

CMD ["/bin/bash","-c","echo 'Start Home Assistant placeholder' && tail -f /dev/null"]
