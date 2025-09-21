#!/usr/bin/env bash
set -euo pipefail

# Fix ownership of git-tracked files that are owned by root.
# Usage: run from repository root: sudo ./scripts/fix-perms.sh

ME=${SUDO_USER:-$(whoami)}

printf "Fixing git-tracked files owned by root to %s:%s\n" "$ME" "$ME"

# List tracked files owned by root and chown them back to the invoking user
git ls-files -z | xargs -0 -I{} bash -c '
  owner=$(stat -c "%U" "{}" 2>/dev/null || true)
  if [ "$owner" = "root" ]; then
    echo "chown $ME:$ME {}"
    chown "$ME":"$ME" "{}"
  fi
' || true

printf "Done.\n"
