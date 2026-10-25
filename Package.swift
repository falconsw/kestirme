// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kestirme",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kestirme",
            path: "Sources/Kestirme",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
