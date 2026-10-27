// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTGViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MTGViewer",
            path: "Sources/MTGViewer",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ],
    swiftLanguageModes: [.v5]
)
