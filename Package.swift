// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VLCKit",
    products: [
        .library(
            name: "VLCKit",
            targets: [
              "VLCKit",
            ]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(name: "VLCKit",
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha17/vlckit-ios-4.0.0-a16-aloha17-vlckit-ios.zip",
                      checksum: "c7a0bd030c6a06589d8bed1a136ed4c53f78e0162a6044277d59e5f643bf8991"),
    ]
)
