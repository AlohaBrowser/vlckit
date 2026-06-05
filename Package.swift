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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha16/vlckit-ios-4.0.0-a16-aloha16-vlckit-ios.zip",
                      checksum: "2cb65424c7a5de2c8f04b8d0f3133048b2afe8e0d627c5847bcd6e6aaf16b11a"),
    ]
)
