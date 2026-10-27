// swift-tools-version: 6.0
import PackageDescription

// No dependencies at all: the app has ~6 preferences in
// UserDefaults and nothing to persist, so there is no GRDB here either.
let package = Package(
    name: "FoldAwayCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FoldAwayCore", targets: ["FoldAwayCore"])
    ],
    targets: [
        .target(name: "FoldAwayCore"),
        .testTarget(name: "FoldAwayCoreTests", dependencies: ["FoldAwayCore"]),
    ]
)
