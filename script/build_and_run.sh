#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexLauncher"
BUNDLE_ID="com.pixionfilm.CodexLauncher"
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
DIST_DIR="dist"
BUNDLE_PATH="$DIST_DIR/$APP_NAME.app"
BUILD_CONFIGURATION="debug"
OPEN_APP=true

for argument in "$@"; do
  if [[ "$argument" == "--release" ]]; then
    BUILD_CONFIGURATION="release"
  elif [[ "$argument" == "--no-open" ]]; then
    OPEN_APP=false
  fi
done

EXECUTABLE_PATH=".build/$BUILD_CONFIGURATION/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  swift build -c release
else
  swift build
fi

rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS" "$BUNDLE_PATH/Contents/Resources"
cp "$EXECUTABLE_PATH" "$BUNDLE_PATH/Contents/MacOS/$APP_NAME"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$BUNDLE_PATH/Contents/Resources/AppIcon.icns"
fi
cat > "$BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE_PATH"

if [[ "$OPEN_APP" == true ]]; then
  /usr/bin/open -n "$BUNDLE_PATH"
fi

if [[ " $* " == *" --verify "* ]]; then
  sleep 1
  pgrep -x "$APP_NAME" >/dev/null
  echo "$APP_NAME is running"
fi
