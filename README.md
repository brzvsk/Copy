# Copy

An open-source clipboard manager for macOS — a visual shelf for everything you
copy, with pinboards, search, and a paste stack.

> ⚠️ Early development. Not ready for daily use yet.

## Building

Requirements: macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

    xcodegen generate
    xcodebuild -project Copy.xcodeproj -scheme Copy -configuration Debug build

Core engine tests:

    swift test --package-path CopyCore

## Releasing

Signed, notarized release DMGs are built locally (CI cannot hold the Developer ID
signing identity). See `Scripts/release.sh` for the full archive, sign, notarize,
staple, and Sparkle-enclosure pipeline, and `docs/appcast.xml` for the Sparkle
update feed. A tag push (`v*`) also runs `.github/workflows/release.yml`, which
builds and tests an unsigned convenience artifact for CI verification only.

    Scripts/release.sh 0.1.0 --dry-run   # build + sign a DMG without publishing
    Scripts/release.sh 0.1.0             # full pipeline, including notarization

## License

GPL-3.0 — see [LICENSE](LICENSE).
