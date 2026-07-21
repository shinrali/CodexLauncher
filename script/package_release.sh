#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexLauncher"
VERSION="$(tr -d '[:space:]' < VERSION)"
DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-v$VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

./script/build_and_run.sh --release --no-open

cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
