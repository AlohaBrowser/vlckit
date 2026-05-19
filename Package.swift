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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha08/vlckit-ios-4.0.0-a16-aloha08-vlckit-ios.zip",
                      checksum: "5efb6a8400639ab82d22474f840e6a48240dcf6048cb76f6cd0e44f0815049a2"),
    ]
)
