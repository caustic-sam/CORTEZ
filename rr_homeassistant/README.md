:warning: rr-homeassistant
=========================

This folder contains a practical scaffold to run Home Assistant on a Raspberry Pi host using
docker-compose. It is intentionally opinionated toward container deployments where you keep
the Home Assistant configuration in the repository (`./config`) so you can edit it from VS Code
and deploy to the Pi.

Included
- `docker-compose.yml` — compose file using the official Home Assistant image and an example macvlan network.
- `Dockerfile` — a lightweight dev Dockerfile (left as-is for local testing).
- `scripts/hacs_install.sh` — idempotent one-shot HACS installer that places HACS into `./config/custom_components/hacs`.

Quick start (development)
1. Copy or create your Home Assistant `config/` inside this folder.
2. Run locally for testing:

```bash
cd rr-homeassistant
docker compose up --build
```

**Deploying to the Pi with a static LAN IP (macvlan)**

- Target static IP: 192.168.1.25/24 (gateway 192.168.1.254). The `docker-compose.yml` includes
  an example `rpi_net` macvlan network configured for this subnet.
- Many operators prefer creating the macvlan network on the Pi host and marking it as external in the
  compose file. Example host command (replace `eth0` with your Pi's uplink interface):

```bash
sudo docker network create -d macvlan \
  --subnet=192.168.1.0/24 --gateway=192.168.1.254 \
  -o parent=eth0 rpi_macvlan
```

Then edit `docker-compose.yml` to set the `rpi_net` network to `external: true` or attach the container
to the host-created network.

HACS installer
- The `hacs-installer` service is provided as a convenience to download the latest HACS release into
  `./config/custom_components/hacs`. It is disabled by default. To run it:

```bash
cd rr-homeassistant
# edit docker-compose.yml: remove the default sleep command for hacs-installer
```markdown
# rr-homeassistant

This folder contains a practical scaffold to run Home Assistant on a Raspberry Pi host using
docker-compose. It is opinionated for container deployments where you keep the Home Assistant
configuration in the repository (`./config`) so you can edit it from VS Code and deploy to the Pi.

Included
- `docker-compose.yml` — compose file using the official Home Assistant image and an example macvlan network.
- `Dockerfile` — a lightweight dev Dockerfile (left as-is for local testing).
- `scripts/hacs_install.sh` — idempotent one-shot HACS installer that places HACS into `./config/custom_components/hacs`.

Quick start (development)
1. Copy or create your Home Assistant `config/` inside this folder.
2. Run locally for testing:

```bash
cd rr-homeassistant
docker compose up --build
```

Deploying to the Pi with a static LAN IP (macvlan)

- Target static IP example: 192.168.1.25/24 (gateway 192.168.1.254). The `docker-compose.yml` includes
  an example `rpi_net` macvlan network configured for this subnet.
- Recommended: create the macvlan network on the Pi host and mark it external in the compose file. Replace
  `eth0` with your Pi's uplink interface when running the host command below:

```bash
sudo docker network create -d macvlan \
  --subnet=192.168.1.0/24 --gateway=192.168.1.254 \
  -o parent=eth0 rpi_macvlan
```

Then set the `rpi_net` network in `docker-compose.yml` to `external: true` or attach the container to the
host-created network.

HACS installer
- The `hacs-installer` service is provided as a convenience to download HACS into
  `./config/custom_components/hacs`. It is disabled by default. To run it:

```bash
cd rr-homeassistant
# edit docker-compose.yml: remove the default sleep command for hacs-installer
docker compose up hacs-installer
```

After the installer completes, restart Home Assistant and finish the HACS setup from the UI.

Persistence & VS Code editing
- Keep your `config/` folder inside this repo so edits in VS Code are immediately available to the container.
- When files are created by root on the Pi, use a fix-permissions helper (for example, `scripts/fix-perms.sh`) or
  run `chown` to ensure the Home Assistant process user can read/write the files.

Notes & next steps
- For production-grade deployments consider using the official Home Assistant OS or Supervisor if you need
  the full add-on ecosystem; Supervisor requires greater host privileges and is not recommended for multi-tenant
  Docker hosts.
- I can: (a) update the compose to use an external host macvlan network and set a fixed IPv4, (b) add a small
  CI check that builds the image and validates compose, or (c) harden the HACS install script to verify signatures.

If you want me to proceed with any of those, tell me which and I'll open a PR on `rr-homeassistant` with the changes.
```
