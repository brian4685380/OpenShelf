#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PNG="$PROJECT_ROOT/Assets/AppIcon.png"
ICONSET="$PROJECT_ROOT/Assets/AppIcon.iconset"
ICNS="$PROJECT_ROOT/Assets/AppIcon.icns"

if [ ! -f "$ICON_PNG" ]; then
    echo "Missing icon PNG: $ICON_PNG"
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png"
sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png"
sips -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png"
sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png"
sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"

echo "Created:"
echo "$ICNS"
