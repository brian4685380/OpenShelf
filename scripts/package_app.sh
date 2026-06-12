#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OpenShelf"
BUNDLE_ID="com.brianyuan.OpenShelf"
VERSION="0.1.0"
BUILD_NUMBER="1"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_ROOT/$APP_NAME.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
ICON_PATH="$PROJECT_ROOT/Assets/AppIcon.icns"

echo "Building release executable..."
cd "$PROJECT_ROOT"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH"
mkdir -p "$RESOURCES_PATH"

echo "Copying executable..."
cp "$PROJECT_ROOT/.build/release/$APP_NAME" "$MACOS_PATH/$APP_NAME"
chmod +x "$MACOS_PATH/$APP_NAME"

if [ -f "$ICON_PATH" ]; then
    echo "Copying app icon..."
    cp "$ICON_PATH" "$RESOURCES_PATH/AppIcon.icns"
else
    echo "Warning: App icon not found at $ICON_PATH"
fi

echo "Writing Info.plist..."
cat > "$CONTENTS_PATH/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>

    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <key>LSUIElement</key>
    <true/>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "Ad-hoc signing app..."
codesign --force --deep --sign - "$APP_PATH"

echo "Done:"
echo "$APP_PATH"
echo
echo "Test with:"
echo "open \"$APP_PATH\""
echo
echo "Install with:"
echo "rm -rf /Applications/$APP_NAME.app && cp -R \"$APP_PATH\" /Applications/"
