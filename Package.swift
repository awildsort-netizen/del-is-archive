// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "del-is-archive",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "del-is-archive", targets: ["DelIsArchive"])
    ],
    targets: [
        .executableTarget(
            name: "DelIsArchive",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
