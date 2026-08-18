// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MDReader",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MDReader", targets: ["MDReader"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "MDReader",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/MDReader"
        )
    ]
)
