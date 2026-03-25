// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "PrivacyShield",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "PrivacyShield", targets: ["PrivacyShield"])
    ],
    targets: [
        .executableTarget(
            name: "PrivacyShield",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
