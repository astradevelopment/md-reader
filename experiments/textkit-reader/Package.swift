// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Probe",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Probe",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        )
    ]
)
