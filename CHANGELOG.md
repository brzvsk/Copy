# Changelog

All notable changes to Copy are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-07-30

A refinement release: the Paste Stack is rebuilt from the ground up, the shelf and
editor get a polish pass, and there's an optional dark theme.

### Added

- Optional pro-dark shelf theme (dark with an electric-blue accent), off by default
- Hold Command to reveal keyboard hotkey hints on the shelf, plus a dismissible keyboard legend
- Force-click a card to preview it; force-click a text card to open it in the editor
- Favorites now sort to the top of the shelf, separated from the rest by a divider
- A first-copy coach and onboarding motion to make the shelf easier to discover

### Changed

- Rebuilt the Paste Stack palette: clicks land reliably everywhere, you can add, edit, remove, and reorder queued items, drag the header to move it, and edit text in the full rich editor
- Redesigned the rich text editor with formatting hotkeys, on-screen tips, and Command-Return to save
- The card header now shows the copy's title where the app name used to be; click it to rename
- You can scroll the shelf from anywhere, including the gaps between cards
- Image cards are labeled "Image" with a photo icon in the header
- Dropping a card onto a pinboard now opens that pinboard
- Larger, easier-to-hit menu and icon buttons throughout

### Fixed

- Cards highlight instantly on click (removed a delay caused by the double-click gesture)
- The installer's DMG background is lighter so its icon labels stay legible

## [0.1.0] - 2026-07-29

Initial release.

### Added

**The shelf**
- Menu bar app with a bottom shelf summoned by ⇧⌘V, showing clipboard history as cards
- Unlimited history with instant full-text search
- Scope chips to filter by type: All, Text, Images, Links, Files
- Space bar preview of the selected card
- Drag-out support to drop a card wherever you need it

**Organizing**
- Pinboards: tabs you can drag cards into, switched with ⌘1-9
- Multi-select for bulk actions
- Edit-in-place for text cards before pasting
- Link previews with page titles and favicons for copied URLs

**Pasting**
- Paste selected card (⏎) or paste as plain text (⌥⏎)
- Paste stack (⌃⌥⌘V) that walks its queue on successive plain ⌘V presses

**Privacy and settings**
- Per-app privacy exclusions
- Respect for the system concealed-type marker, so password managers and
  similar apps are never recorded
- Configurable history retention
- A Settings window for all of the above

**Onboarding and polish**
- First-run onboarding covering the Accessibility permission, the clipboard
  access permission on macOS 15.4+, and the global hotkey
- A permission banner in the shelf when Accessibility access is missing
- A native app icon
- Auto-updates via Sparkle
- Native design throughout: quiet cards, SF Mono for card bodies, no colored
  stripes
