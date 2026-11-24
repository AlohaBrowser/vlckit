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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha21/vlckit-ios-4.0.0-a16-aloha21-vlckit-ios.zip",
                      checksum: "52fbe14a137244c07f0fcee782df7d97000be0d5f66b7b5e2d5ad1dca5a1d773"),
    ]
)
