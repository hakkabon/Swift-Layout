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
        // Pure-Swift tests that don't need the layout engine itself —
        // NodeIDAllocator's id-stability contract today; a natural home
        // for GraphPlacement's offset math too, since that's also a pure
        // function with no FFI dependency. Anything exercising the actual
        // FFI call belongs in Sample-App instead, against real flatteners
        // and real graphs.
        .testTarget(
            name: "SwiftLayoutTests",
            dependencies: ["SwiftLayout"]
        ),
        // The Auto-Injected Binary Target
        .binaryTarget(
            name: "LayoutFFI",
            url: "https://github.com/hakkabon/Layout/releases/download/v0.0.2/Layout.xcframework.zip",
            checksum: "59adeb902ab693dad9e62f19feea90cf0a869ba3b5b9da95015597b062edfdd7"
        )
    ]
)
