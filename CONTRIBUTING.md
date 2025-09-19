# Contributing to Cortex

A short, practical contributing guide for changes to `cortex_master.sh` and repository expectations.

Before you open a PR

- Run a syntax check: `bash -n cortex_master.sh`
- Optional lint: `shellcheck cortex_master.sh` (install locally if needed)
- Keep changes small and focused: prefer editing a single function in `cortex_master.sh` per PR.
- No secrets in commits: placeholders such as `BORG_PASSPHRASE` must remain placeholders.

PR content expectations

- Title: short, descriptive (e.g., "docker_install(): add daemon.json opt-in logging")
- Description: 2–4 lines: what changed, why, and rollback steps.
- Files changed: prefer a single edited function or a small set (function + README or helper script).
- Idempotency note: every PR that modifies runtime behavior must include a line confirming the change is idempotent or explain why it isn't.

Testing guidance

- For script-only changes, include the results of `bash -n cortex_master.sh` in the PR description.
- If the change affects systemd units or helper scripts, include a short smoke-test recipe (2–3 commands) to validate on-device.

Code review focus

- Safety on re-run (idempotency)
- Avoid hard-coded vendor IDs or secrets
- Correct ownership/permissions when creating files (`chown -R "$STACK_USER":stack /opt/containers` pattern)

If you modify systemd units

- Prefer changing the generator function in `cortex_master.sh`. If a change is urgent, propose a systemd drop-in and include the drop-in contents and reload steps in the PR description.

Thanks — small, safe patches are preferred for this project.
