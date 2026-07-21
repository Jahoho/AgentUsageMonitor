#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/releases/AgentUsageMonitor.app}"
BUNDLE_DIR="$APP_DIR/Contents/Resources/AgentUsageMonitor_AgentUsageMonitor.bundle"
EXECUTABLE="$APP_DIR/Contents/MacOS/AgentUsageMonitor"
ICON_FILE="$APP_DIR/Contents/Resources/AgentUsageMonitor.icns"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

fail() {
  echo "$1" >&2
  exit 1
}

verify_signature() {
  local clean_check_dir
  local clean_app_dir

  if ! /usr/bin/codesign --verify --deep --verbose=2 "$APP_DIR"; then
    fail "Invalid or incomplete app signature: $APP_DIR"
  fi

  # A Desktop/FileProvider checkout can attach FinderInfo to a valid app after
  # packaging. Verify the exact sealed contents again from a metadata-free copy
  # so strict validation remains meaningful without mutating the source bundle.
  clean_check_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/agent-usage-monitor-signature.XXXXXX")"
  clean_app_dir="$clean_check_dir/AgentUsageMonitor.app"
  trap '/bin/rm -rf "$clean_check_dir"' EXIT

  /usr/bin/ditto --norsrc --noextattr "$APP_DIR" "$clean_app_dir"
  if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$clean_app_dir"; then
    fail "App contents fail strict signature verification: $APP_DIR"
  fi

  /bin/rm -rf "$clean_check_dir"
  trap - EXIT
}

expect_plist_value() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null)" \
    || fail "Missing Info.plist key: $key"
  [[ "$actual" == "$expected" ]] \
    || fail "Unexpected Info.plist $key: expected '$expected', got '$actual'"
}

if [[ ! -x "$EXECUTABLE" ]]; then
  fail "Missing executable: $EXECUTABLE"
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  fail "Missing resource bundle: $BUNDLE_DIR"
fi

if [[ ! -f "$ICON_FILE" ]]; then
  fail "Missing app icon: $ICON_FILE"
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  fail "Missing Info.plist: $INFO_PLIST"
fi

for logo in codex.png claude.png deepseek.png openrouter.svg; do
  if [[ ! -f "$BUNDLE_DIR/$logo" ]]; then
    fail "Missing logo resource: $BUNDLE_DIR/$logo"
  fi
done

expect_plist_value "CFBundleIdentifier" "local.agent-usage-monitor"
expect_plist_value "CFBundleExecutable" "AgentUsageMonitor"
expect_plist_value "CFBundlePackageType" "APPL"
expect_plist_value "LSMinimumSystemVersion" "14.0"
expect_plist_value "LSUIElement" "true"

verify_signature

echo "Package verified: $APP_DIR"
