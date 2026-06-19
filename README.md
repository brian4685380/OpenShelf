# OpenShelf

<p align="center">
  <strong>A lightweight, open-source file shelf for macOS.</strong>
</p>

<p align="center">
  Temporarily collect files, keep them within reach, and drag them wherever you need.
</p>

---

OpenShelf is a native macOS utility inspired by file-shelf applications such as DropShelf.

Drag files to the left or right edge of the screen to reveal a floating shelf. Files placed on the shelf remain easily accessible while you work across applications, Desktops, and fullscreen spaces.

OpenShelf is designed to stay minimal: it runs quietly from the menu bar, uses native SwiftUI and AppKit components, and does not upload or modify your files unless you explicitly drag them somewhere.

## Features

- Reveal the shelf by dragging files to either screen edge
- Position the shelf near the location where the drag was triggered
- Temporarily store references to files and folders
- Drag files from the shelf into Finder or other applications
- Drag files back into the shelf
- Open files with a double-click
- Reveal files in Finder
- Copy file paths
- Remove individual items or clear the entire shelf
- Automatically remove entries when their original files no longer exist
- Collapse into a slim screen-edge tab when not in use
- Remain available across macOS Desktops and fullscreen applications
- Native menu bar integration
- Lightweight native macOS implementation
- No analytics, accounts, or cloud services

## Why OpenShelf?

Moving files between Finder windows and applications often requires repeatedly navigating through folders or keeping several windows open.

OpenShelf provides a temporary staging area:

1. Drag files to the edge of the screen.
2. Keep them on the shelf while switching applications.
3. Drag them to their destination when needed.

The shelf stores references to the original files rather than creating its own copies.

## Installation

1. Download the latest `.dmg` file from the [Releases](../../releases) page.
2. Open the downloaded DMG.
3. Drag `OpenShelf.app` into the `Applications` folder.
4. Launch OpenShelf from Applications.

OpenShelf runs as a menu bar application and does not appear in the Dock.

> OpenShelf is currently distributed without Apple notarization. On the first launch, macOS may require you to Control-click the app, select **Open**, and confirm.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac, depending on the provided release build

## Usage

1. Launch OpenShelf.
2. Drag a file or folder to the left or right edge of the screen.
3. Drop it onto the shelf.
4. Drag it from the shelf into Finder or another application when needed.

Additional actions are available from each item's context menu.

## Current Status

OpenShelf is under active development.

The current release supports the core single-file shelf workflow. Multi-selection and dragging multiple shelf items at once are planned for a future release.

Bug reports, feature suggestions, and contributions are welcome.

## Build from Source

### Prerequisites

- macOS 13 or later
- Xcode Command Line Tools
- Swift toolchain

Clone the repository:

```bash
git clone https://github.com/brian4685380/OpenShelf.git
cd OpenShelf
```

Run the app:

```bash
swift run
```

Build an optimized release:

```bash
swift build -c release
```

## Packaging

To create the `.app`, `.zip`, and `.dmg` release artifacts:

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh 0.2.0
```

Generated files will be placed in:

```text
dist/
├── OpenShelf.app
├── OpenShelf-v0.2.0-macOS.zip
└── OpenShelf-v0.2.0-macOS.dmg
```

## Built With

- Swift
- SwiftUI
- AppKit
- Swift Package Manager

## Privacy

OpenShelf works locally on your Mac.

It does not:

- upload files
- collect analytics
- require an account
- connect to external services

## Roadmap

- Multi-selection
- Dragging multiple files at once
- Improved release signing and notarization
- Additional shelf customization
- Keyboard shortcuts
- Improved accessibility

## Contributing

Contributions are welcome.

You can help by:

- reporting bugs
- suggesting improvements
- improving documentation
- submitting pull requests

For substantial changes, please open an issue first to discuss the proposed implementation.

## License

OpenShelf is open-source software. See the [`LICENSE`](LICENSE) file for details.
