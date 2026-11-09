// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mustel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "mustel", targets: ["Mustel"])],
    targets: [
        .executableTarget(
            name: "Mustel",
            resources: [
                .copy("MustelMenuBar.png"),
                .copy("FlutterDefaultIcon.png"),
                .copy("FlutterLicense.txt"),
                .copy("Animations")
            ]
        ),
        .testTarget(
            name: "MustelTests",
            dependencies: ["Mustel"]
        )
    ]
)
