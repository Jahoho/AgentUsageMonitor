#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_APP_DIR="${1:-$ROOT_DIR/releases/AgentUsageMonitor.app}"
INSTALLED_APP_DIR="${2:-/Applications/AgentUsageMonitor.app}"
OLD_INSTALLED_APP_DIR="/Applications/Agent Usage Monitor.app"
STAGING_APP_DIR="/Applications/.AgentUsageMonitor.app.installing"
BACKUP_APP_DIR="/Applications/.AgentUsageMonitor.app.previous"

"$ROOT_DIR/scripts/verify-package.sh" "$RELEASE_APP_DIR"
"$ROOT_DIR/scripts/verify-package.sh" "$INSTALLED_APP_DIR"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP_DIR"; then
  echo "Installed app fails strict on-disk signature verification." >&2
  exit 1
fi

if ! /usr/bin/diff -qr "$RELEASE_APP_DIR" "$INSTALLED_APP_DIR" >/dev/null; then
  echo "Installed app differs from release package." >&2
  exit 1
fi

for unexpected_app in "$OLD_INSTALLED_APP_DIR" "$STAGING_APP_DIR" "$BACKUP_APP_DIR"; do
  if [[ -e "$unexpected_app" ]]; then
    echo "Unexpected old or temporary app bundle remains: $unexpected_app" >&2
    exit 1
  fi
done

echo "Installation verified: $INSTALLED_APP_DIR"
