# Baseline snapshot

Date: 2025-09-19

This file marks the baseline snapshot for the project. It records the commit/tag that represents the "line in the sand" start of development.

Tagged as: `v0.1.0`

Commit: the commit on branch `fix/systemd-timeout-compose` that added a conservative TimeoutStartSec to the generated systemd unit and initial docs (CONTRIBUTING.md, .github/copilot-instructions.md).

Why: create a reproducible reference point for future work. Use this tag when you need to revert or branch off a clean starting state.

How to use:

- To check out this baseline locally:
  - git fetch --all --tags
  - git checkout tags/v0.1.0 -b baseline/v0.1.0

- To roll back (use with caution): revert the commit or reset main to this tag after discussion and review.

Notes:

- This is a lightweight, documented baseline for a lean workflow. For stronger guarantees, consider enabling branch protection on `main` and creating a GitHub Release (created automatically with this tag).
