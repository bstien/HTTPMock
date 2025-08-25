// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HTTPMock",
    products: [
        .library(name: "HTTPMock", targets: ["HTTPMock"]),
    ],
    targets: [
        .target(name: "HTTPMock"),
        .testTarget(
            name: "HTTPMockTests",
            dependencies: ["HTTPMock"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
