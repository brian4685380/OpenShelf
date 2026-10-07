# Releasing OpenShelf

Releases target Apple Silicon and macOS 13+. Package on an arm64 Mac. Developer ID signing and notarization are not configured; do not describe these builds as notarized.

## Prepare

1. Confirm `main` is up to date and inspect the worktree. Do not discard unrelated changes.
2. Update `OpenShelfVersion.current` in `sources/ShelfCore/ShelfCLIArguments.swift` and `CHANGELOG.md`. The packager reads this version and rejects a conflicting argument.
3. Run `swift test` and `swift build -c release`. Confirm GitHub CI is green for the release commit before publishing.
4. Exercise the native checklist in [CONTRIBUTING.md](../CONTRIBUTING.md), including hot/cold CLI starts. Empty the shelf or save its temporary content before quitting the running app; contents are session-only.

## Package and inspect

```sh
./scripts/package_app.sh 0.8.0
./scripts/verify_release.sh 0.8.0
```

Outputs: `dist/OpenShelf.app`, standalone `shelf`, versioned ZIP/DMG, `SHA256SUMS`, and `openshelf.rb`. The first package run installs pinned `dmgbuild` in a local `.build` virtual environment. Older versioned archives are preserved.

The verifier checks bundle metadata, arm64 binaries, the bundled CLI, signatures, ZIP contents, cask version/checksum, and the DMG's Applications link/background/layout metadata. Open the DMG in Finder as well and confirm the drag-to-Applications instruction is legible.

Copy the generated cask into `Casks/openshelf.rb` in this repository, then commit the release changes. Do not use `sha256 :no_check`.

## Publish GitHub

Use a new immutable version/tag. Do not replace assets for an existing public version.

```sh
git push origin main
gh run list --workflow ci.yml
# Wait for CI on the exact commit, then:
git tag -a v0.8.0 -m "OpenShelf v0.8.0"
git push origin v0.8.0
gh release create v0.8.0 --verify-tag --title "OpenShelf v0.8.0" \
  --notes-file docs/releases/v0.8.0.md \
  dist/OpenShelf-v0.8.0-macOS.zip \
  dist/OpenShelf-v0.8.0-macOS.dmg dist/SHA256SUMS
```

Download the published assets into a separate temporary directory and verify `shasum -a 256 -c SHA256SUMS` there. A successful upload is not checksum verification.

## Update the existing Homebrew tap

The maintainer's local tap is `/opt/homebrew/Library/Taps/brian4685380/homebrew-openshelf`. It is a separate repository; do not nest a new clone in OpenShelf or create another `/tmp` clone.

```sh
TAP=/opt/homebrew/Library/Taps/brian4685380/homebrew-openshelf
git -C "$TAP" status --short
git -C "$TAP" pull --ff-only
cp dist/openshelf.rb "$TAP/Casks/openshelf.rb"
brew style "$TAP/Casks/openshelf.rb"
brew audit --cask brian4685380/openshelf/openshelf
brew fetch --cask brian4685380/openshelf/openshelf
git -C "$TAP" add Casks/openshelf.rb
git -C "$TAP" commit -m "Update OpenShelf to 0.8.0"
git -C "$TAP" push
```

Verify the remote cask version, URL and checksum match the published ZIP. Test installation/upgrade in a disposable app directory or after safely quitting the current app. Check `shelf --version` and a file addition, not just the symlink's existence.
