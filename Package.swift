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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha03/vlckit-ios-4.0.0-a16-aloha03-vlckit-ios.zip",
                      checksum: "ce033525ecc9412c3a9bf6c1acb418676da0c0dc19a66690a507a6fbd0a7e81a"),
    ]
)
