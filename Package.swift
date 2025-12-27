// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnkiToMarkdown",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AnkiToMarkdown",
            targets: ["AnkiToMarkdown"]
        ),
        .executable(
            name: "anki-export",
            targets: ["anki-export"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        .package(url: "https://github.com/awxkee/zstd.swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AnkiToMarkdown",
            dependencies: [
                "SWCompression",
                .product(name: "zstd", package: "zstd.swift")
            ]
        ),
        .testTarget(
            name: "AnkiToMarkdownTests",
            dependencies: ["AnkiToMarkdown"]
        ),
        .executableTarget(
            name: "anki-export",
            dependencies: ["AnkiToMarkdown"]
        ),
    ]
)
