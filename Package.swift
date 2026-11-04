// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mustel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "mustel", targets: ["Mustel"])],
    targets: [
        .executableTarget(
            name: "Mustel",
            resources: [.copy("MustelMenuBar.png")]
        ),
        .testTarget(
            name: "MustelTests",
            dependencies: ["Mustel"]
        )
    ]
)
