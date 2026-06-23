#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# OpenShelf release packager
#
# Outputs:
#   dist/OpenShelf.app
#   dist/shelf
#   dist/OpenShelf-v<VERSION>-macOS.zip
#   dist/OpenShelf-v<VERSION>-macOS.dmg
#   dist/openshelf.rb
#
# Usage:
#   ./scripts/package_app.sh
#   ./scripts/package_app.sh 0.4.1
# ============================================================

APP_NAME="OpenShelf"
CLI_NAME="shelf"
VERSION="${1:-0.4.1}"
BUNDLE_IDENTIFIER="com.brianyuan.OpenShelf"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build"
DIST_DIR="${PROJECT_ROOT}/dist"

export CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${BUILD_DIR}/ModuleCache"
export XDG_CACHE_HOME="${BUILD_DIR}/swiftpm-cache"

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

ZIP_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}-macOS.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}-macOS.dmg"
CLI_PATH="${DIST_DIR}/${CLI_NAME}"
CASK_PATH="${DIST_DIR}/openshelf.rb"
DMG_BACKGROUND_PATH="${BUILD_DIR}/DMGBackground.png"
DMGBUILD_VENV="${BUILD_DIR}/dmgbuild-venv"
DMGBUILD="${DMGBUILD_VENV}/bin/dmgbuild"

ICON_SOURCE="${PROJECT_ROOT}/Assets/AppIcon.icns"
MENU_BAR_ICON_SOURCE="${PROJECT_ROOT}/Assets/AppIcon.png"
DMG_BACKGROUND_GENERATOR="${PROJECT_ROOT}/scripts/create_dmg_background.swift"
DMG_SETTINGS="${PROJECT_ROOT}/scripts/dmg_settings.py"

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
swift build -c release --disable-sandbox

EXECUTABLE_PATH="$(
    swift build -c release --disable-sandbox --show-bin-path
)/${APP_NAME}"
CLI_EXECUTABLE_PATH="$(
    swift build -c release --disable-sandbox --show-bin-path
)/${CLI_NAME}"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
    echo "Error: executable was not found:"
    echo "  ${EXECUTABLE_PATH}"
    exit 1
fi

if [[ ! -f "${CLI_EXECUTABLE_PATH}" ]]; then
    echo "Error: CLI executable was not found:"
    echo "  ${CLI_EXECUTABLE_PATH}"
    exit 1
fi

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cp "${CLI_EXECUTABLE_PATH}" "${MACOS_DIR}/${CLI_NAME}"
chmod +x "${MACOS_DIR}/${CLI_NAME}"

cp "${CLI_EXECUTABLE_PATH}" "${CLI_PATH}"
chmod +x "${CLI_PATH}"

# ------------------------------------------------------------
# Copy icon when available
# ------------------------------------------------------------

ICON_PLIST_ENTRY=""

if [[ -f "${ICON_SOURCE}" ]]; then
    echo "Copying app icon..."
    cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.icns"
    cp "${MENU_BAR_ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.png"
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

ZIP_SHA256="$(
    shasum -a 256 "${ZIP_PATH}" | awk '{print $1}'
)"

cat > "${CASK_PATH}" <<EOF
cask "openshelf" do
  version "${VERSION}"
  sha256 "${ZIP_SHA256}"

  url "https://github.com/brian4685380/OpenShelf/releases/download/v#{version}/OpenShelf-v#{version}-macOS.zip"
  name "OpenShelf"
  desc "Lightweight file shelf for macOS"
  homepage "https://github.com/brian4685380/OpenShelf"

  depends_on macos: :ventura

  app "OpenShelf.app"
  binary "#{appdir}/OpenShelf.app/Contents/MacOS/shelf", target: "shelf"

  uninstall quit: "com.brianyuan.OpenShelf"

  zap trash: [
    "~/Library/Preferences/com.brianyuan.OpenShelf.plist",
  ]
end
EOF

# ------------------------------------------------------------
# Create DMG with deterministic Finder metadata
# ------------------------------------------------------------

echo
echo "Creating DMG..."

swift \
    "${DMG_BACKGROUND_GENERATOR}" \
    "${DMG_BACKGROUND_PATH}"

if [[ ! -x "${DMGBUILD}" ]]; then
    echo "Installing pinned DMG packaging dependency..."
    python3 -m venv "${DMGBUILD_VENV}"
    "${DMGBUILD_VENV}/bin/python" -m pip install \
        --disable-pip-version-check \
        "dmgbuild==1.6.7"
fi

"${DMGBUILD}" \
    -s "${DMG_SETTINGS}" \
    -D "app=${APP_BUNDLE}" \
    -D "background=${DMG_BACKGROUND_PATH}" \
    "${APP_NAME}" \
    "${DMG_PATH}"

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
echo "  CLI: ${CLI_PATH}"
echo "  ZIP: ${ZIP_PATH}"
echo "  DMG: ${DMG_PATH}"
echo "  Homebrew Cask: ${CASK_PATH}"
echo
echo "Recommended GitHub release asset:"
echo "  $(basename "${DMG_PATH}")"
echo
echo "Recommended Homebrew cask source:"
echo "  ${CASK_PATH}"
