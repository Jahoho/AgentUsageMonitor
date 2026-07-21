#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/releases/AgentUsageMonitor.app"
STAGING_APP_DIR="$ROOT_DIR/releases/.AgentUsageMonitor.app.packaging"
BACKUP_APP_DIR="$ROOT_DIR/releases/.AgentUsageMonitor.app.previous"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RESOURCE_BUNDLE_NAME="AgentUsageMonitor_AgentUsageMonitor.bundle"
BUILD_RESOURCE_BUNDLE="$ROOT_DIR/.build/release/$RESOURCE_BUNDLE_NAME"
APP_RESOURCE_BUNDLE="$RESOURCES_DIR/$RESOURCE_BUNDLE_NAME"
ICON_FILE="$ROOT_DIR/Packaging/AppIcon/AgentUsageMonitor.icns"

cleanup() {
  /bin/rm -rf "$STAGING_APP_DIR"
}

rollback() {
  /bin/rm -rf "$APP_DIR"
  if [[ -d "$BACKUP_APP_DIR" ]]; then
    /bin/mv "$BACKUP_APP_DIR" "$APP_DIR"
  fi
}

trap cleanup EXIT

if [[ -d "$BACKUP_APP_DIR" && ! -d "$APP_DIR" ]]; then
  /bin/mv "$BACKUP_APP_DIR" "$APP_DIR"
elif [[ -d "$BACKUP_APP_DIR" ]]; then
  /bin/rm -rf "$BACKUP_APP_DIR"
fi

cd "$ROOT_DIR"
swift "$ROOT_DIR/scripts/generate-app-icon.swift"
swift build -c release

if [[ ! -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  echo "Missing resource bundle: $BUILD_RESOURCE_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "Missing app icon: $ICON_FILE" >&2
  exit 1
fi

/bin/rm -rf "$STAGING_APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/AgentUsageMonitor" "$MACOS_DIR/AgentUsageMonitor"
cp "$ROOT_DIR/Packaging/AgentUsageMonitor.Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ICON_FILE" "$RESOURCES_DIR/AgentUsageMonitor.icns"
/usr/bin/ditto "$BUILD_RESOURCE_BUNDLE" "$APP_RESOURCE_BUNDLE"

# Seal the completed local bundle so Gatekeeper can verify that its plist and
# resources belong to the executable. This is an ad-hoc signature only; public
# distribution still requires Developer ID signing and notarization.
/usr/bin/xattr -cr "$STAGING_APP_DIR"
/usr/bin/codesign --force --sign - "$STAGING_APP_DIR"

"$ROOT_DIR/scripts/verify-package.sh" "$STAGING_APP_DIR"

if [[ -d "$APP_DIR" ]]; then
  /bin/mv "$APP_DIR" "$BACKUP_APP_DIR"
fi

if ! /bin/mv "$STAGING_APP_DIR" "$APP_DIR"; then
  rollback
  echo "Packaging failed while replacing the release bundle; the previous package was restored." >&2
  exit 1
fi

# Desktop sync providers can add Finder metadata when the bundle becomes a
# visible .app. Verify the sealed contents without racing that metadata writer.
if ! "$ROOT_DIR/scripts/verify-package.sh" "$APP_DIR"; then
  rollback
  echo "Final package signature verification failed; the previous package was restored." >&2
  exit 1
fi

/bin/rm -rf "$BACKUP_APP_DIR"
trap - EXIT

echo "Packaged $APP_DIR"
