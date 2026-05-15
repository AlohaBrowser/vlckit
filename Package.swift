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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha04/vlckit-ios-4.0.0-a16-aloha04-vlckit-ios.zip",
                      checksum: "30eccc0a440fe02393dbe62b96ef086959ed3e0d843f6eb4679e7c9bddcd5f91"),
    ]
)
