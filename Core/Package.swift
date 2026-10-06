// swift-tools-version:5.9
//
// GlyphCore is the UI-free logic of Glyphfinder (database, search, code formats, keyboard mapping).
// The Xcode project compiles these same source files straight into the app target; this package exists
// so the logic can be built and tested anywhere with `swift test` (including Linux CI).
import PackageDescription

let package = Package(
    name: "GlyphCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlyphCore", targets: ["GlyphCore"]),
    ],
    targets: [
        .target(name: "GlyphCore", path: "Sources/GlyphCore"),
        .testTarget(
            name: "GlyphCoreTests",
            dependencies: ["GlyphCore"],
            path: "Tests/GlyphCoreTests"
        ),
    ]
)
