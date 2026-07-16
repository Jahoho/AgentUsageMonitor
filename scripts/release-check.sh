#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --check
    "$ROOT_DIR/scripts/security-check.sh"
else
    echo "Source archive detected; skipping Git repository checks."
fi

swift test
"$ROOT_DIR/scripts/package-app.sh"
"$ROOT_DIR/scripts/verify-package.sh"

echo "Release checks passed. Quit the running app, then run ./scripts/install-app.sh."
