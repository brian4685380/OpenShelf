#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# OpenShelf release packager
#
# Outputs:
#   dist/OpenShelf.app
#   dist/OpenShelf-v<VERSION>-macOS.zip
#   dist/OpenShelf-v<VERSION>-macOS.dmg
#
# Usage:
#   ./scripts/package_app.sh
#   ./scripts/package_app.sh 0.2.0
# ============================================================

APP_NAME="OpenShelf"
VERSION="${1:-0.2.0}"
BUNDLE_IDENTIFIER="com.brianyuan.OpenShelf"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build"
DIST_DIR="${PROJECT_ROOT}/dist"

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

ZIP_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}-macOS.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}-macOS.dmg"
DMG_STAGING_DIR="${DIST_DIR}/dmg"

ICON_SOURCE="${PROJECT_ROOT}/Assets/AppIcon.icns"

echo "Packaging ${APP_NAME} v${VERSION}"
echo "Project: ${PROJECT_ROOT}"

# ------------------------------------------------------------
# Clean previous output
# ------------------------------------------------------------

rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# ------------------------------------------------------------
# Build optimized executable
# ------------------------------------------------------------

echo
echo "Building release executable..."

cd "${PROJECT_ROOT}"
swift build -c release

EXECUTABLE_PATH="$(
    swift build -c release --show-bin-path
)/${APP_NAME}"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
    echo "Error: executable was not found:"
    echo "  ${EXECUTABLE_PATH}"
    exit 1
fi

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# ------------------------------------------------------------
# Copy icon when available
# ------------------------------------------------------------

ICON_PLIST_ENTRY=""

if [[ -f "${ICON_SOURCE}" ]]; then
    echo "Copying app icon..."
    cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.icns"
    ICON_PLIST_ENTRY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    echo "Warning: ${ICON_SOURCE} does not exist."
    echo "The app will use the default macOS executable icon."
fi

# ------------------------------------------------------------
# Create Info.plist
# ------------------------------------------------------------

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC
    "-//Apple//DTD PLIST 1.0//EN"
    "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>

    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>

    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>${APP_NAME}</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <key>LSUIElement</key>
    <true/>

    <key>NSHighResolutionCapable</key>
    <true/>

    ${ICON_PLIST_ENTRY}
</dict>
</plist>
EOF

plutil -lint "${CONTENTS_DIR}/Info.plist"

# ------------------------------------------------------------
# Ad-hoc sign the app
#
# This is suitable for local/open-source unsigned distribution.
# For a public trusted release, replace "-" with your
# Developer ID Application certificate and notarize it.
# ------------------------------------------------------------

echo
echo "Applying ad-hoc signature..."

codesign \
    --force \
    --deep \
    --sign - \
    "${APP_BUNDLE}"

codesign --verify --deep --strict "${APP_BUNDLE}"

# ------------------------------------------------------------
# Create ZIP
#
# ditto preserves the macOS bundle metadata better than zip -r.
# ------------------------------------------------------------

echo
echo "Creating ZIP..."

ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "${APP_BUNDLE}" \
    "${ZIP_PATH}"

# ------------------------------------------------------------
# Create DMG staging directory
# ------------------------------------------------------------

echo
echo "Creating DMG..."

mkdir -p "${DMG_STAGING_DIR}"

cp -R "${APP_BUNDLE}" "${DMG_STAGING_DIR}/${APP_NAME}.app"

ln -s \
    "/Applications" \
    "${DMG_STAGING_DIR}/Applications"

# ------------------------------------------------------------
# Build compressed DMG
# ------------------------------------------------------------

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING_DIR}"

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

echo
echo "Verifying generated app..."

codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "${APP_BUNDLE}"

echo
echo "Release artifacts created:"
echo "  App: ${APP_BUNDLE}"
echo "  ZIP: ${ZIP_PATH}"
echo "  DMG: ${DMG_PATH}"
echo
echo "Recommended GitHub release asset:"
echo "  $(basename "${DMG_PATH}")"
