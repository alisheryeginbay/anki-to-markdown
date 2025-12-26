// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnkiToMarkdown",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AnkiToMarkdown",
            targets: ["AnkiToMarkdown"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
    ],
    targets: [
        .target(
            name: "AnkiToMarkdown",
            dependencies: ["SWCompression"]
        ),
        .testTarget(
            name: "AnkiToMarkdownTests",
            dependencies: ["AnkiToMarkdown"]
        ),
    ]
)
