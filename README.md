# Copy

A visual shelf for everything you copy.

Copy is a free, open-source clipboard manager for macOS. Press ⇧⌘V and a
shelf of cards slides up from the bottom of your screen showing your
clipboard history, ready to search, pin, and paste back in.

![Copy shelf screenshot](docs/screenshot.png)

*Screenshot coming soon.*

## Features

**The shelf**
- Summon with ⇧⌘V from any app; every copy becomes a card, instantly searchable
- Unlimited history with full-text search and scope chips (All / Text / Images / Links / Files)
- Space bar previews a card full-screen before you commit to pasting it
- Drag any card out of the shelf and drop it wherever you need it

**Organizing**
- Pinboards: drag a card into a tab to keep it around, switch tabs with ⌘1-9
- Multi-select for bulk actions
- Edit a card's text in place before pasting it
- Link previews show the page title and favicon for copied URLs

**Pasting**
- ⏎ pastes the selected card as-is; ⌥⏎ strips formatting and pastes plain text
- Paste stack: queue up several cards and walk through them on successive ⌘V presses

**Privacy**
- Everything stays on your Mac. No accounts, no cloud sync, no telemetry
- Respects the system's concealed-type marker, so password managers and other
  apps that mark their clipboard contents as sensitive are never recorded
- Per-app exclusions let you block specific apps from being captured at all
- Configurable history retention

**Housekeeping**
- Native menu bar app, quiet by design (no colored stripes, no clutter)
- First-run onboarding walks through the permissions Copy needs and why
- Auto-updates via Sparkle

## Install

### Homebrew (recommended)

```
brew install --cask tarikbc/tap/copy
```

### Direct download

Grab the latest DMG from [Releases](https://github.com/tarikbc/Copy/releases),
open it, and drag Copy to Applications.

Requires macOS 14 or later.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘V | Open the shelf |
| ← / → | Move selection |
| ⏎ | Paste selected card |
| ⌥⏎ | Paste as plain text |
| Space | Preview selected card |
| ⌘⌫ | Delete selected card |
| ⌘1-9 | Switch to history / pinboard tab |
| ⌃⌥⌘V | Toggle the paste stack |
| ⌘E | Edit selected card in place |

## Build from source

Requirements: macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
xcodegen generate
xcodebuild -project Copy.xcodeproj -scheme Copy -configuration Debug build
```

Core engine tests:

```
swift test --package-path CopyCore
```

### Cutting a release

Signed, notarized release DMGs are built locally (CI cannot hold the
Developer ID signing identity). See `Scripts/release.sh` for the full
archive, sign, notarize, staple, and Sparkle-enclosure pipeline, and
`docs/appcast.xml` for the Sparkle update feed. A tag push (`v*`) also runs
`.github/workflows/release.yml`, which builds and tests an unsigned
convenience artifact for CI verification only.

```
Scripts/release.sh 0.1.0 --dry-run   # build + sign a DMG without publishing
Scripts/release.sh 0.1.0             # full pipeline, including notarization
```

## Privacy

Copy is local-only, with one exception: link previews fetch the page title
and favicon for copied links directly from the web. This is on by default
and can be turned off in Settings under History. Aside from that and
checking for app updates, Copy makes no network calls, has no analytics or
crash reporting, and your clipboard history never leaves your Mac. Any app
that marks its pasteboard content as concealed, such as a password manager,
is skipped entirely, and you can add per-app exclusions in Settings for
anything else you would rather Copy ignore.

## Auto-updates

Copy checks for updates automatically using [Sparkle](https://sparkle-project.org).
You can also trigger a check manually from the menu bar item with
"Check for Updates…".

## Contributing

Issues and pull requests are welcome. The core clipboard engine lives in
`CopyCore` and has its own test suite (`swift test --package-path CopyCore`);
please add or update tests for any engine changes.

## License

GPL-3.0. See [LICENSE](LICENSE).
