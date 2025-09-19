<!-- .github/copilot-instructions.md -->
# Guidance for AI coding agents working on Cortex

This repository is a small utility/installer for Raspberry Pi 5 Docker hosts. Primary artifact: `cortex_master.sh` (a single, idempotent bash bootstrap script that scaffolds packages, users, Docker, systemd units, and optional features such as an "AI HAT").

Keep responses short and actionable. Prefer concrete edits to the codebase (small, focused patches). When making changes, reference the exact file and function (for example: `cortex_master.sh::docker_install()`).

Key project facts (what to know immediately)
- Single primary implementation: `cortex_master.sh` — a root-run bash script organized into discrete functions (e.g., `apt_hygiene`, `docker_install`, `compose_scaffold`, `ai_hat_setup`). Edit or add functions rather than creating many new shell entrypoints.
- Idempotency: functions are written to be re-runnable on the same host. Preserve this pattern when changing behavior (check for existing files/users/groups before creating them).
- Systemd integration: the script writes systemd unit files into `/etc/systemd/system/` (examples: `rpicortex-stack@.service`, `borgmatic.timer`, `rpi-weekly-health.timer`). When proposing or editing services, update both the unit file template and any associated helper scripts under `/usr/local/bin` or `/opt/containers`.
- Service users and groups: `STACK_USER=svc_stack`, `BACKUP_USER=svc_backup` and group `stack` are used for privileges; changes to permissions or sudoers must reference `/etc/sudoers.d/80-stack` created by the script.
- AI HAT: `ai_hat_setup()` contains placeholders and conservative defaults (udev rule, docker service drop-in) — adjust only with vendor docs present. Avoid inventing vendor IDs.

Developer workflows (explicit commands / examples)
- To run the installer locally (intended on a Raspberry Pi as root):
  - sudo bash cortex_master.sh
- To test small changes without rebooting the host, prefer running individual functions in a safe environment or on a disposable VM/container. Example: run only Docker install section by copying `docker_install()` into a test shell and invoke it.
- To enable the compose stack after editing `/opt/containers/docker-compose.yml`:
  - sudo systemctl enable --now rpicortex-stack@up.service
  - Stop: sudo systemctl stop rpicortex-stack@up.service; Start down: sudo systemctl start rpicortex-stack@down.service

Project-specific conventions and patterns
- Prefer explicit checks (e.g., `id -u user &>/dev/null || useradd ...`) rather than unconditional creation. Keep `set -euo pipefail` at the script top when adding new scripts.
- When adding files under `/opt/containers` or `/etc/rpicortex`, maintain the directory ownership model: `chown -R "$STACK_USER":stack /opt/containers` and `chmod -R g+rw` where the script does so.
- Keep documentation inline: the script writes helpful README files (e.g., `/etc/rpicortex/ai-hat-readme.txt`); update those when you add functionality.

Integration & external dependencies (what to watch for)
- The script installs from external apt repositories (Docker official repo via `download.docker.com`). Network access and correct `VERSION_CODENAME` are required.
- Borg backup configuration contains a placeholder `BORG_PASSPHRASE` — do not commit real secrets. If adding automation around secrets, prefer referencing a secrets manager (note placeholders exist).

When proposing changes, follow this pattern
1. Small, focused patch touching one function or template file.
2. Preserve idempotency and careful checks for existing state.
3. Include a short rationale comment in code and in the PR description explaining the safety and rollback considerations for performing the change on a live Pi.

Reference files that illustrate the above patterns
- `cortex_master.sh` — primary implementation (read top-to-bottom; functions are independent units).
- `README.md` — minimal; update only to add usage or testing notes.

If any behavior is unclear, ask these concrete questions:
- "Do you want this change to be safe to re-run on an existing device (idempotent)?"
- "Should the change modify systemd unit templates or helper scripts under `/usr/local/bin`?"
- "Is this change allowed to add network/apt repo calls, or must it be offline-safe?"

After adding or changing system-level behavior, provide a brief smoke test (2–3 commands) demonstrating how to verify the change on-device.

Try it — quick smoke tests (safe, copyable)

Run these locally to validate the script without doing a full install. Prefer a disposable VM or container when running actions that change system state.

```bash
# Syntax check
bash -n cortex_master.sh

# Lint (optional)
shellcheck cortex_master.sh || echo "install shellcheck for more checks"

# Search for key templates / functions
grep -n "rpicortex-stack@.service" cortex_master.sh || true
grep -n "ai_hat_setup" cortex_master.sh || true

# After running the installer on a test Pi, verify expected outcomes
docker --version || echo "docker not found"
id svc_stack || echo "svc_stack user missing"
sudo systemctl status rpicortex-stack@up.service --no-pager || true
ls -l /opt/containers/_env/rpicortex.example.env || true
```

Example: safe systemd unit edits (pattern)

When you need to change a systemd unit created by the script, prefer either:

- Update the template in `cortex_master.sh` (the function that writes the unit) and propose a small patch that keeps the write idempotent; or
- Add a drop-in override on-device rather than editing the generated unit directly. Example drop-in (safe, reload + restart):

```bash
sudo mkdir -p /etc/systemd/system/rpicortex-stack@.service.d
sudo tee /etc/systemd/system/rpicortex-stack@.service.d/10-override.conf <<'EOF'
[Service]
# Example: increase timeout or change WorkingDirectory if needed
TimeoutStartSec=120
EOF
sudo systemctl daemon-reload
sudo systemctl restart rpicortex-stack@up.service
```

When proposing a change in a PR, prefer editing the function in `cortex_master.sh` that scaffolds the unit (search for `rpicortex-stack@.service` in the script). Include a short rationale in the commit/PR describing why the change is idempotent and how to roll it back.

End of file.
