// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Desk2ShellApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Desk2Shell", targets: ["Desk2ShellApp"])
    ],
    targets: [
        .executableTarget(
            name: "Desk2ShellApp",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "Desk2ShellAppTests",
            dependencies: ["Desk2ShellApp"]
        )
    ]
)
