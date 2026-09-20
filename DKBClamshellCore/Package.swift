// swift-tools-version: 6.0
import PackageDescription

// No dependencies at all (plan §3.2 D13): the app has ~6 preferences in
// UserDefaults and nothing to persist, so there is no GRDB here either.
let package = Package(
    name: "DKBClamshellCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DKBClamshellCore", targets: ["DKBClamshellCore"])
    ],
    targets: [
        .target(name: "DKBClamshellCore"),
        .testTarget(name: "DKBClamshellCoreTests", dependencies: ["DKBClamshellCore"]),
    ]
)
