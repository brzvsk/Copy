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

## License

GPL-3.0 — see [LICENSE](LICENSE).
