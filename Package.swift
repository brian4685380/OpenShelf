// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenShelf",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenShelf", targets: ["OpenShelf"]),
        .executable(name: "shelf", targets: ["ShelfCLI"]),
    ],
    targets: [
        .executableTarget(
            name: "OpenShelf",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "ShelfCLI",
            path: "sources/ShelfCLI",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
