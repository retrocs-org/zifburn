// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZIFburn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZIFburn",
            path: "Sources/ZIFburn"
        ),
        .testTarget(
            name: "ZIFburnTests",
            dependencies: ["ZIFburn"],
            path: "Tests/ZIFburnTests"
        ),
    ]
)
