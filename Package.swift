// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Freundeblick",
    defaultLocalization: "de",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Freundeblick", targets: ["Freundeblick"])
    ],
    targets: [
        .executableTarget(
            name: "Freundeblick",
            path: "Sources/Freundeblick"
        ),
        .testTarget(
            name: "FreundeblickTests",
            dependencies: ["Freundeblick"],
            path: "Tests/FreundeblickTests"
        )
    ]
)
