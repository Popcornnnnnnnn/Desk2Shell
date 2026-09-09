// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Desk2ShellApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Desk2Shell", targets: ["Desk2ShellApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Desk2ShellApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.copy("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "Desk2ShellAppTests",
            dependencies: ["Desk2ShellApp"]
        )
    ]
)
