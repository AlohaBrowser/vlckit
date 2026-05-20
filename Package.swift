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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha11/vlckit-ios-4.0.0-a16-aloha11-vlckit-ios.zip",
                      checksum: "2092440dd581d07af5ed939572e157f31adb386d6c671d1cb89bd84a6ac5a711"),
    ]
)
