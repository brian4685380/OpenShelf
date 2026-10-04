#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(sed -n 's/.*public static let current = "\([^"]*\)".*/\1/p' "${ROOT}/sources/ShelfCore/ShelfCLIArguments.swift")}"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 1; }
DIST="${ROOT}/dist"
ZIP="${DIST}/OpenShelf-v${VERSION}-macOS.zip"
DMG="${DIST}/OpenShelf-v${VERSION}-macOS.dmg"
WORK="$(mktemp -d "${TMPDIR:-/tmp}"/openshelf-verify.XXXXXX)"
# Canonicalize TMPDIR so cleanup does not depend on /var vs /private/var aliases.
WORK="$(cd "${WORK}" && pwd -P)"
MOUNT="${WORK}/mount"
MOUNTED=0
cleanup() {
    if [[ "${MOUNTED}" == 1 ]]; then
        if ! hdiutil detach "${MOUNT}" >/dev/null; then
            echo "Could not detach ${MOUNT}; leaving verification directory intact." >&2
            return
        fi
    fi
    rm -rf "${WORK}"
}
trap cleanup EXIT

(cd "${DIST}" && shasum -a 256 -c SHA256SUMS)
ditto -x -k "${ZIP}" "${WORK}/zip"
APP="${WORK}/zip/OpenShelf.app"
PLIST="${APP}/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")" == "${VERSION}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${PLIST}")" == "13.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST}")" == "com.brianyuan.OpenShelf" ]]
[[ -s "${APP}/Contents/Resources/AppIcon.icns" && -s "${APP}/Contents/Resources/AppIcon.png" ]]
codesign --verify --deep --strict "${APP}"
for executable in OpenShelf shelf; do
    [[ -x "${APP}/Contents/MacOS/${executable}" ]]
    [[ "$(lipo -archs "${APP}/Contents/MacOS/${executable}")" == "arm64" ]]
done
"${APP}/Contents/MacOS/shelf" --version | grep -Fx "shelf ${VERSION}"
"${APP}/Contents/MacOS/shelf" --help >/dev/null
grep -Fq "version \"${VERSION}\"" "${DIST}/openshelf.rb"
SHA="$(shasum -a 256 "${ZIP}" | awk '{print $1}')"
grep -Fq "sha256 \"${SHA}\"" "${DIST}/openshelf.rb"

mkdir "${MOUNT}"
hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT}" "${DMG}" >/dev/null
MOUNTED=1
[[ "$(readlink "${MOUNT}/Applications")" == "/Applications" ]]
[[ -s "${MOUNT}/.DS_Store" ]]
[[ -s "${MOUNT}/.background.png" ]]
codesign --verify --deep --strict "${MOUNT}/OpenShelf.app"
cmp "${APP}/Contents/MacOS/OpenShelf" "${MOUNT}/OpenShelf.app/Contents/MacOS/OpenShelf"
hdiutil detach "${MOUNT}" >/dev/null
MOUNTED=0
echo "Verified OpenShelf ${VERSION}: metadata, signature, CLI, ZIP, DMG, checksums and cask."
