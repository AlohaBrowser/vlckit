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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha13/vlckit-ios-4.0.0-a16-aloha13-vlckit-ios.zip",
                      checksum: "99b56ae8e0369534390e1633f7732c0dbf8a4d541bffcc9409a91eefeb5d476b"),
    ]
)
