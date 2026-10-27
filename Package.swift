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
        ),
        .testTarget(name: "TutorTests", dependencies: ["Tutor"], path: "Tests/TutorTests"),
    ],
    swiftLanguageModes: [.v5]
)
