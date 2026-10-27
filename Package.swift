// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tutor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tutor",
            path: "Sources/Tutor",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ],
    swiftLanguageModes: [.v5]
)
