# Changelog

All notable changes to Copy are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
