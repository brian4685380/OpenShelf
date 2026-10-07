# Changelog

## 0.8.0 — 2026-10-07

### Added

- Multiple independent shelves with a plain OpenShelf title and separate contents, order, selection, pinning, and floating windows.
- New Shelf from the menu bar, header + button, or shelf-local ⌘N; a shelf switcher and explicit removal action in the menu bar.
- Active-shelf CLI routing, filename previews in the shelf menu, and new-shelf creation on screen-edge drags even on occupied edges. Direct content-area drops still add to the shelf under the pointer.
- Cross-shelf file/group dragging, with independent ownership of imported temporary clips.

### Fixed

- Adding files to an expanded, manually positioned shelf no longer snaps it back to an edge.
- Keep each full-panel fallback drop destination aligned when its shelf is moved.
- Copying temporary content between shelves no longer leaves references dependent on the source shelf's lifetime.
- Edge re-entry during the same drag reuses its preview; canceled empty previews are hidden for reuse without disturbing existing shelves.

## 0.7.0 — 2026-10-04

### Added

- Shelf-local keyboard navigation, range selection, Select All, Copy Files, Copy Paths, Quick Look, Open, Remove and Escape actions.
- Pin button and ⌘P to keep the shelf expanded, including when empty.
- Selected/total item count, explicit accessibility labels and row actions, full-path tooltips, and a Paste from Clipboard button.
- Menu-bar shortcut guide and About dialog.
- `shelf --help`, `--version`, literal filenames after `--`, and acknowledged CLI delivery with meaningful exit codes.
- A private, expiring request/reply queue recovers CLI delivery when distributed wake-up notifications are missed.
- macOS CI, issue templates, contributor/security/release documentation, and reproducible light/dark README screenshots.

### Fixed

- Open file-monitor descriptors on a bounded background queue, preventing slow filesystem/permission checks from freezing the shelf and CLI processing.
- Reconcile missing files in the background while watcher setup is pending, so deleted entries do not linger behind a blocked descriptor open.
- Keep copied/exported temporary files alive until quit, allowing destinations to read them after their shelf entries are removed.
- Floating-window recovery after Desktop, fullscreen, wake, and display changes without disrupting in-progress Finder drops.
- A vertical row-reorder gesture can become a file drag when it exits any shelf side, retaining the original selected group and anchoring the preview to the cursor.
- Clipboard paste and CLI additions now use the same selection-clearing and feedback path as drops.
- Keyboard navigation scrolls off-screen rows into view without interfering with mouse selection or drag auto-scrolling.
- CLI retries acknowledge a request once instead of repeatedly moving/showing the shelf; invalid input is rejected before adding any paths.

### Distribution

- Version consistency checks, scoped packaging cleanup, bundled CLI smoke checks, and published ZIP/DMG checksums.
- Still macOS 13+, Apple Silicon release artifacts, and ad-hoc signed (not notarized).

## 0.6.0

Reliable full-panel native drops, consecutive Finder drops without an edge trigger, and expanded regression coverage for selection, reordering, scrolling, CLI, clipboard, appearance and packaging.

Earlier release notes are available on [GitHub Releases](https://github.com/brian4685380/OpenShelf/releases).
