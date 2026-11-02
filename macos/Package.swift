// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChojemaCopyKeep",
    defaultLocalization: "ko",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ChojemaCopyKeep", targets: ["CopyKeep"])],
    targets: [
        .executableTarget(name: "CopyKeep", resources: [.copy("Resources")],
                          linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "CopyKeepTests", dependencies: ["CopyKeep"])
    ]
)
