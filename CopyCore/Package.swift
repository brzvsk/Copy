// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopyCore", targets: ["CopyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "CopyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "CopyCoreTests", dependencies: ["CopyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
