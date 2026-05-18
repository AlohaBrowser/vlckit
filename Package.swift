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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha05/vlckit-ios-4.0.0-a16-aloha05-vlckit-ios.zip",
                      checksum: "b769db132f52e61ee45377643fff53704dfd4b06ca7c8075ea02ffaad533d23c"),
    ]
)
