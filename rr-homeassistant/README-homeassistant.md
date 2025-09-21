rr-homeassistant
===============

This folder contains a minimal template for running Home Assistant in a container for development.

What is included

- `Dockerfile` — minimal, non-root container template (use official images for production).
- `docker-compose.yml` — example compose file mounting `./config` and `./deps`.

Quick start (development)

1. Copy your Home Assistant `config/` into this directory or mount an external folder.
2. Build and run:

```bash
cd rr-homeassistant
docker compose up --build
```

Notes

- This is a safe development scaffold — it intentionally does not install full Home Assistant packages. For production, use the official images and follow Home Assistant's documentation.
- Ensure the `config` directory is owned by a non-root user when running as a non-root container.
