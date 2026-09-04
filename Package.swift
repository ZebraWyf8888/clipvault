// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipVault",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClipVaultCore"),
        .executableTarget(name: "ClipVault", dependencies: ["ClipVaultCore"]),
        .executableTarget(name: "cvdump", dependencies: ["ClipVaultCore"]),
        .testTarget(name: "ClipVaultCoreTests", dependencies: ["ClipVaultCore"]),
    ]
)
