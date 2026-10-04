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
            dependencies: ["ShelfCore"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "ShelfCLI",
            dependencies: ["ShelfCore"],
            path: "sources/ShelfCLI",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .target(name: "ShelfCore", path: "sources/ShelfCore"),
        .testTarget(
            name: "OpenShelfTests",
            dependencies: ["OpenShelf", "ShelfCore"],
            path: "Tests/OpenShelfTests"
        ),
    ]
)
