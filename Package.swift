// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OKXMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OKXMenuBar", targets: ["OKXMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "OKXMenuBar",
            path: "Sources/OKXMenuBar"
        )
    ]
)
