#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/releases/AgentUsageMonitor.app"
DEST_DIR="/Applications/AgentUsageMonitor.app"
OLD_DEST_DIR="/Applications/Agent Usage Monitor.app"
STAGING_DEST_DIR="/Applications/.AgentUsageMonitor.app.installing"
BACKUP_DEST_DIR="/Applications/.AgentUsageMonitor.app.previous"

cleanup() {
  /bin/rm -rf "$STAGING_DEST_DIR"
}

rollback() {
  /bin/rm -rf "$DEST_DIR"
  if [[ -d "$BACKUP_DEST_DIR" ]]; then
    /bin/mv "$BACKUP_DEST_DIR" "$DEST_DIR"
  fi
}

trap cleanup EXIT

if /usr/bin/pgrep -x AgentUsageMonitor >/dev/null; then
  echo "AgentUsageMonitor is running. Quit it before installing a replacement." >&2
  exit 1
fi

if [[ -d "$BACKUP_DEST_DIR" && ! -d "$DEST_DIR" ]]; then
  /bin/mv "$BACKUP_DEST_DIR" "$DEST_DIR"
elif [[ -d "$BACKUP_DEST_DIR" ]]; then
  /bin/rm -rf "$BACKUP_DEST_DIR"
fi

/bin/rm -rf "$STAGING_DEST_DIR"

"$ROOT_DIR/scripts/package-app.sh"
"$ROOT_DIR/scripts/verify-package.sh" "$APP_DIR"
/usr/bin/ditto --norsrc --noextattr "$APP_DIR" "$STAGING_DEST_DIR"
"$ROOT_DIR/scripts/verify-package.sh" "$STAGING_DEST_DIR"

if [[ -d "$DEST_DIR" ]]; then
  /bin/mv "$DEST_DIR" "$BACKUP_DEST_DIR"
fi

if ! /bin/mv "$STAGING_DEST_DIR" "$DEST_DIR"; then
  rollback
  echo "Install failed while replacing the app; the previous version was restored." >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/verify-package.sh" "$DEST_DIR" \
  || ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST_DIR"; then
  rollback
  echo "Installed package verification failed; the previous version was restored." >&2
  exit 1
fi

if ! /usr/bin/diff -qr "$APP_DIR" "$DEST_DIR" >/dev/null; then
  rollback
  echo "Installed package differs from the release build; the previous version was restored." >&2
  exit 1
fi

/bin/rm -rf "$BACKUP_DEST_DIR"
/bin/rm -rf "$OLD_DEST_DIR"
"$ROOT_DIR/scripts/verify-installation.sh"
trap - EXIT

echo "Installed $DEST_DIR"
