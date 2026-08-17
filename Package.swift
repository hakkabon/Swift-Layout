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
            url: "https://github.com/hakkabon/Layout/releases/download/v0.0.1/Layout.xcframework.zip",
            checksum: "eb2b8a9039d5982359b994761db70a50507ce04d61d37bbe8a40f941b114e486"
        )
    ]
)
