// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Desks",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Desks",
            path: "Sources/Desks"
        )
    ]
)
