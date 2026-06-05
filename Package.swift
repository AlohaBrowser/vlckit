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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha15/vlckit-ios-4.0.0-a16-aloha15-vlckit-ios.zip",
                      checksum: "66bea36e28f06cd844d7a7ab61d3f15aa631d4065022fa91332f6f137a545c59"),
    ]
)
