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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha07/vlckit-ios-4.0.0-a16-aloha07-vlckit-ios.zip",
                      checksum: "b7e8aae7cb82d83de8c4f0da397e4e6d4020e03b86dcc1a7e92951c7c3353c4e"),
    ]
)
