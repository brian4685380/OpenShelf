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
- Select one or more shelf items
- Drag multiple selected files from the shelf into Finder or other applications
- Drag files back into the shelf
- Manually reorder shelf rows by dragging them up or down
- Auto-scroll while drag-selecting or reordering long shelves
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

### Homebrew

Homebrew is the recommended way to install OpenShelf if you want the `shelf`
CLI to be available automatically.

After the Homebrew tap is published:

```bash
brew tap brian4685380/openshelf
brew install --cask openshelf
```

Homebrew installs `OpenShelf.app` and links the bundled `shelf` command into
Homebrew's bin directory.

```bash
shelf ~/Desktop/example.pdf ~/Downloads/example-folder
```

### DMG

1. Download the latest `.dmg` file from the [Releases](../../releases) page.
2. Open the downloaded DMG.
3. Drag `OpenShelf.app` into the `Applications` folder.
4. Launch OpenShelf from Applications.

OpenShelf runs as a menu bar application and does not appear in the Dock.

> OpenShelf is currently distributed without Apple notarization. On the first launch, macOS may require you to Control-click the app, select **Open**, and confirm.

### Optional CLI

OpenShelf also includes a command-line tool named `shelf`.

If you install with Homebrew, the CLI is linked automatically. If you install
from the DMG, you can expose the CLI from the OpenShelf menu bar item:

1. Click the OpenShelf menu bar icon.
2. Select **Install CLI Tool…**.
3. Enter your macOS administrator password when prompted.

This creates the following symlink:

```bash
sudo ln -sf /Applications/OpenShelf.app/Contents/MacOS/shelf /usr/local/bin/shelf
```

If OpenShelf is already running, the files are added to the current shelf. If it
is not running, the CLI attempts to launch OpenShelf first and then adds the
files.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac, depending on the provided release build

## Usage

1. Launch OpenShelf.
2. Drag a file or folder to the left or right edge of the screen.
3. Drop it onto the shelf.
4. Drag it from the shelf into Finder or another application when needed.

Shelf interactions:

- Click a row to select it.
- Command-click rows to add or remove individual items from the selection.
- Drag across the empty shelf area to select multiple rows, similar to Finder.
- Drag selected rows out of the shelf to move multiple files at once.
- Drag rows up or down inside the shelf to manually reorder them.
- Run `shelf <file-or-folder> [...]` from Terminal to add files directly.

Additional actions are available from each item's context menu.

## Current Status

OpenShelf is under active development.

The current v0.3.0 release supports the core shelf workflow, multi-selection, dragging multiple selected items, manual row reordering, adaptive light/dark appearance, and improved DMG installation guidance.

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
./scripts/package_app.sh 0.3.0
```

The first packaging run creates a local virtual environment under `.build/`
and installs the pinned `dmgbuild` dependency used to generate Finder layout
metadata reliably.

Generated files will be placed in:

```text
dist/
├── OpenShelf.app
├── shelf
├── OpenShelf-v0.3.0-macOS.zip
├── OpenShelf-v0.3.0-macOS.dmg
└── openshelf.rb
```

The generated `dist/openshelf.rb` file contains the release ZIP checksum and can
be copied into a Homebrew tap repository under `Casks/openshelf.rb`.

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
