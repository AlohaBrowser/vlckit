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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha20/vlckit-ios-4.0.0-a16-aloha20-vlckit-ios.zip",
                      checksum: "aba47e23e221a2a8bae900ecc6085693766333edf26db010d3f2454936e1da9d"),
    ]
)
