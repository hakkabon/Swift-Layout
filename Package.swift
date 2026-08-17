// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftLayout",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15)
    ],
    products: [
        .library(name: "SwiftLayout", targets: ["SwiftLayout"])
    ],
    dependencies: [],
    targets: [
        // The Swift Wrapper Source Target
        .target(
            name: "SwiftLayout",
            dependencies: ["LayoutFFI"]
        ),
        // The Auto-Injected Binary Target
        .binaryTarget(
            name: "LayoutFFI",
            url: "https://github.com/hakkabon/Layout/releases/download/v0.0.6/Layout.xcframework.zip",
            checksum: "482bcbea1cf332dce642dea1831517dde4975283e10284ac2f9a910a0564982a"
        )
    ]
)
