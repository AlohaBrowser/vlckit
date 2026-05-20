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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha10/vlckit-ios-4.0.0-a16-aloha10-vlckit-ios.zip",
                      checksum: "3fa9ebb4336f1ace954203b3edc440d18c0217e93237d0af74ae504aee9e5874"),
    ]
)
