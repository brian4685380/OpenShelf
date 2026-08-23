# OpenShelf requirement and regression audit

This checklist consolidates the behavior requested during the development of
OpenShelf through v0.6.0. A release is considered regression-safe only when
every applicable item below has code-level evidence and either an automated or
live macOS verification.

## Visual design and distribution

| ID | Acceptance criterion | Verification |
| --- | --- | --- |
| VIS-01 | The menu bar item uses `Assets/AppIcon.png`, not a folder or generic app icon. | Bundle/source asset inspection and packaged-app check |
| VIS-02 | Finder and the packaged app use `Assets/AppIcon.icns`. | Info.plist/resource inspection |
| VIS-03 | The DMG contains OpenShelf, an Applications alias, visible drag-to-Applications guidance, and the intended Finder layout. | Mounted-DMG inspection and screenshot |
| VIS-04 | The shelf content background is fully opaque. | Light/dark rendered appearance check |
| VIS-05 | Selected rows have an obvious blue/accent highlight. | Rendered appearance check |
| VIS-06 | Drag selection does not draw a blue marquee rectangle. | Selection-overlay code/test and live check |
| VIS-07 | The shelf follows macOS light and dark appearance; light mode is not rendered black. | Light/dark rendered appearance check |
| VIS-08 | There is no unintended gap between the header and content/first row. | Layout/rendered appearance check |

## Shelf lifecycle and window behavior

| ID | Acceptance criterion | Verification |
| --- | --- | --- |
| WIN-01 | Removing the final item automatically closes the empty shelf. | Controller/content regression test |
| WIN-02 | Clicking non-row content clears the current selection. | Selection hit-test/click regression test |
| WIN-03 | The scrollbar remains directly usable and never starts marquee selection. | Scrollbar hit-test regression test and live check |
| WIN-04 | Selection/reorder auto-scroll stops on mouse release and does not continue scrolling while the pointer is outside the shelf. | Auto-scroll state regression test and live check |
| WIN-05 | Left and right edges work on every connected display, and the shelf appears near the drag position. | Geometry tests and multi-display live check |
| WIN-06 | The shelf remains above other applications, windows/tabs, Desktops, and fullscreen Spaces. | Window configuration tests and live check |
| WIN-07 | Edge triggers remain available after switching apps, windows/tabs, displays, or Spaces. | Refresh/configuration tests and live check |
| WIN-08 | An idle shelf collapses to a slim edge tab after the delay and expands again on hover/drag. | Controller timing/configuration test and live check |

## Finder-like selection and actions

| ID | Acceptance criterion | Verification |
| --- | --- | --- |
| SEL-01 | A shelf with one item allows that row to be clicked and dragged; with two items, both rows work. | Row hit-test/drag-intent regression tests |
| SEL-02 | Command-click toggles individual rows in a multi-selection. | Selection-state regression test |
| SEL-03 | Shift-click selects an anchored contiguous range. | Selection-state regression test |
| SEL-04 | Drag selection begins only in empty/side content, never on a file row. | Selection-overlay hit-test regression test |
| SEL-05 | Dragging over rows selects them; reversing the pointer shrinks the range and deselects rows no longer covered. | Marquee range regression test |
| SEL-06 | Command-drag selection adds the swept range to the existing selection. | Marquee range regression test |
| SEL-07 | Drag selection auto-scrolls near the top/bottom without losing the selected range. | Selection auto-scroll/range regression test and live check |
| SEL-08 | A successful new external drop clears the previous selection. | Content/drop-state regression test |
| SEL-09 | Clicking an already-selected row in a multi-selection preserves the group for drag/action. | Selection-state regression test |
| SEL-10 | Double-click and context-menu actions apply to all selected rows when invoked on a selected row. | Selected-action resolution regression test |
| SEL-11 | Multiple selected files are exported in one drag session. | Selected-drag resolution/pasteboard regression test and live check |

## Manual row ordering

| ID | Acceptance criterion | Verification |
| --- | --- | --- |
| ORD-01 | Items preserve insertion/manual order and are not automatically sorted. | Store regression test |
| ORD-02 | A single row or a selected group can be moved up and down with cursor direction preserved. | Store move and drag-intent regression tests |
| ORD-03 | Reordering shows a blue insertion line at the destination. | Row implementation/rendered appearance check |
| ORD-04 | Reordering auto-scrolls near the visible list's top/bottom. | Reorder auto-scroll regression test and live check |
| ORD-05 | Reordering uses a deliberate threshold, target inset, and cooldown so rows do not vibrate. | Drag-intent/constants regression test and live check |

## Drop, paste, and content import

| ID | Acceptance criterion | Verification |
| --- | --- | --- |
| DROP-01 | Dragging supported content to either screen edge shows `Drop to add` and advertises a copy/plus operation. | Edge destination/drop-state regression test and live check |
| DROP-02 | The entire visible shelf, including rows and surrounding content, accepts external drops. | Panel/container/capture regression tests and live check |
| DROP-03 | During the hide delay, leaving and re-entering the visible shelf restores its drop target. | Edge-capture timing regression test |
| DROP-04 | A second or later file can be dropped directly onto an already-visible shelf without first returning to the edge. | Sequential-drop regression test and live check |
| DROP-05 | Files, folders, images, selected text, web links, legacy Finder file lists, and file promises are accepted. | Importer/type-registration regression tests |
| DROP-06 | Temporary browser-provided image files are copied before their source removes them. | Importer regression test |
| DROP-07 | Command-V over the shelf imports clipboard files, images, or text. | Paste/import/window-event regression tests and live check |
| DROP-08 | Added, duplicate, and unsupported content produce clear feedback; only successful additions clear selection. | Drop-state/content regression tests |

## CLI, cleanup, and release artifacts

| ID | Acceptance criterion | Verification |
| --- | --- | --- |
| CLI-01 | `shelf <path> [...]` adds one or multiple files/folders to an already-running OpenShelf instance. | Receiver/CLI integration check |
| CLI-02 | If OpenShelf is not running, `shelf` launches the installed app and then adds the paths. | Cold-start CLI integration check |
| CLI-03 | Relative paths are normalized, missing paths are reported, and an invocation with no usable path exits unsuccessfully. | CLI process regression checks |
| CLI-04 | OpenShelf enforces one running app instance. | Lock implementation and process integration check |
| CLI-05 | The app bundle contains `Contents/MacOS/shelf`; Homebrew links it; the menu offers an administrator-assisted `/usr/local/bin/shelf` symlink. | Bundle/cask/source inspection |
| DATA-01 | Missing original files are removed from the shelf automatically. | File-monitor regression test |
| DATA-02 | Shelf-managed text/image/link files are deleted when removed or cleared. | Store/import cleanup regression tests |
| DATA-03 | Open, Quick Look, Reveal in Finder, Copy Path, Remove, and Clear Shelf remain available and honor multi-selection where applicable. | Source/action-resolution tests and live menu check |
| REL-01 | README, package defaults, app metadata, cask metadata, supported architecture, and minimum macOS version agree. | Static release audit |
| REL-02 | ZIP and DMG are valid; the ZIP contains the app and bundled CLI; checksums and generated Homebrew cask agree. | Packaging and artifact audit |

## Audit result

Audit date: 2026-08-23

Result: **PASS — no known requirement regression in the audited working tree.**

### Automated regression evidence

The AppKit/SwiftUI test process was run with normal macOS screen and pasteboard
access:

```bash
swift test --disable-sandbox
```

Result: **65 tests executed, 0 failures**.

The suite now directly covers the historical high-risk paths:

- exact menu bar icon source
- one-row and two-row hit testing and drag intent
- Command-click, Shift-click, and selected-group action resolution
- side-area click clearing and scrollbar exclusion
- forward/reverse marquee selection and Command-marquee union
- auto-scroll edge/outside geometry
- manual single/group moves in both directions without automatic sorting
- deliberate reorder threshold, inset, and cooldown
- multi-file drag pasteboard contents
- selection clearing only after a successful drop
- automatic closure after removing the final row
- opaque adaptive light/dark colors and selected-row emphasis
- header-to-first-row layout geometry
- edge and full-visible-shelf drops, hide-delay re-entry, and sequential drops
- all-Spaces/fullscreen window flags, foreground refresh, collapse/expand, and
  trigger-position geometry
- clipboard file/image/text import and Command-V event handling
- browser image, text, link, legacy Finder list, and temporary-file import
- duplicate/error/success feedback
- CLI distributed-command receipt, missing-file cleanup, and managed-file cleanup

### Release and artifact evidence

`./scripts/package_app.sh 0.6.0` completed successfully from the audited tree.
The resulting app passed strict deep code-signature verification, both the app
and bundled CLI are arm64, and the app declares macOS 13.0 as its minimum.

The packaged icon files are byte-for-byte identical to the source assets:

- `AppIcon.png`: `4a8a5cabe392d9e7edd7ae9cad3546f5305d1946b4f13fc7212e6fd326ed3d67`
- `AppIcon.icns`: `7c97ac936c6fd0a03d5949287a6c8a113816f6b193739a6a91789f9a589282`

Final local audit artifacts:

- ZIP: `6d323cf24f27668416ca0949a427fac290344ab3c696fb365968a9fb8fbd5453`
- DMG: `b7980b494bc4d2086d24207ae4a8448eb53b1f161a4ca93f4001db55d36a3947`

The ZIP checksum exactly matches the generated and repository Homebrew casks.

The DMG passed `hdiutil verify`. It was also mounted and opened in Finder. The
final window visibly contained the OpenShelf icon, Applications alias, arrow,
“Install OpenShelf” heading, and “Drag OpenShelf into the Applications folder”
instruction. Its `.DS_Store` records the intended 660×420 window, 128-point
icons, background image, and icon coordinates.

The v0.6.0 release ZIP is the artifact referenced by the repository and
Homebrew tap casks. Publishing the byte-identical ZIP and successfully fetching
it through Homebrew are final release gates.

### Live macOS evidence

- The installed `shelf` symlink resolves to
  `/Applications/OpenShelf.app/Contents/MacOS/shelf`.
- A hot CLI invocation added two relative paths to an already-running current
  build; both rows were visually confirmed in the shelf.
- A cold CLI invocation launched the installed app and added its relative path;
  the row was visually confirmed.
- A forced second launch left exactly one OpenShelf process running.
- The user confirmed the latest cross-window/Space always-on-top behavior in the
  active macOS session.
- In the current debug build, Finder dragged `DirectToMiddle.txt` straight into
  the center of an already-visible shelf without touching either screen edge.
  A second consecutive drag of `DragMouse.swift`, again without an edge visit
  or reopening the shelf, also produced a new row. Both paths emitted the
  visible-content drag event and have automated regressions.

The currently attached-display set was covered by native panel tests. The
multi-display implementation creates left and right trigger panels for every
entry in `NSScreen.screens` and rebuilds them when screen parameters change.
