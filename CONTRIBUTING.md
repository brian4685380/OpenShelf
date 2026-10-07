# Contributing to OpenShelf

Thanks for helping make moving files on macOS less fiddly. Small, well-tested changes are welcome.

## Get started

Use macOS 13+ and Swift 5.9+ (Xcode or Command Line Tools). Quit the installed menu-bar app before running a development build; OpenShelf intentionally allows only one instance.

```sh
swift run OpenShelf
swift test
swift build -c release
```

Tests use AppKit, pasteboards, and screen geometry, so they need a logged-in macOS GUI session. Run them serially: several intentionally present short-lived windows. CLI transport tests use unique notification names so they do not modify your running shelf.

CI runs the full suite on Apple Silicon. Intel CI builds both products and runs non-SwiftUI-rendering regressions; its virtual GPU can abort inside Metal when rendering SwiftUI materials. For Intel UI changes, also test on a physical Intel Mac.

## Where things live

| Directory | Responsibility |
| --- | --- |
| `sources/OpenShelf/App` | Menu bar, process lifecycle, workspace observations |
| `sources/OpenShelf/Controllers` | ShelfManager ownership/routing, shelf/edge panels, focus, collapse and Spaces policy |
| `sources/OpenShelf/Views` | SwiftUI presentation and native drag/selection bridges |
| `sources/OpenShelf/Models` | Ordered items, selection, keyboard commands, pin state |
| `sources/OpenShelf/Store` | File references, group actions, import coordination |
| `sources/OpenShelf/Services` | Content conversion, file monitoring, CLI receiver |
| `sources/ShelfCLI` / `sources/ShelfCore` | Command-line transport, parser, protocol, version |
| `Tests/OpenShelfTests` | Model, native event, geometry, import and controller regressions |
| `scripts` | App bundle, ZIP, DMG and cask generation |

## Before opening a pull request

- Explain the behavior change and how you tested it. Add a regression test for bugs.
- Keep unrelated formatting and generated build files out of the diff.
- For UI changes, include light/dark screenshots and exercise both an empty shelf and one/two-row shelves.
- For drag changes, test Finder → visible shelf twice without touching an edge, multi-row reorder, auto-scroll, and drag-out through all four sides.
- For multi-shelf changes, test direct and cross-shelf drops onto empty shelves and rows, independent selection/pinning, active-shelf CLI delivery, hide/reopen/remove, and temporary-clip survival after the source shelf is cleared. Keep one shared pair of edge triggers per screen, not one pair per shelf.
- For window changes, test switching apps, Desktops, fullscreen, and disconnecting an external display. Unit tests cannot substitute for WindowServer interaction checks.
- Never make the shelf take focus or reorder destination windows during a physical drag. `.floating` is intentional: higher levels have broken Finder drops.
- Removing ordinary file references must never delete the original files. Keep import ownership explicit.
- Avoid logging clipboard text or adding new telemetry/network requests.

Historical behavior and manual acceptance notes are in [the requirements audit](docs/requirements-audit.md).

## Documentation screenshots

Render the actual SwiftUI interface with synthetic fixtures (no personal files):

```sh
OPENSHELF_SCREENSHOTS="$PWD/docs/images" swift test --filter ShelfScreenshotTests
```

Inspect both PNGs before committing. This opt-in renderer is skipped by normal test runs. It is not a substitute for testing real dragging and keyboard focus.

## Reporting issues

Use the issue templates. Include version, macOS, displays/Spaces, source application, expected/actual result, and precise steps. A short recording is especially helpful for drag bugs. Redact personal filenames and paths.

Please discuss large features before implementing them. Favor predictable native behavior, local processing, and a small interface. Be respectful and assume good intent in discussions and reviews.

## Releases

Maintainers: follow [the release checklist](docs/releasing.md). Contributions are licensed under the project's [MIT license](LICENSE).
