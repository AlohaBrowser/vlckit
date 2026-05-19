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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha09/vlckit-ios-4.0.0-a16-aloha09-vlckit-ios.zip",
                      checksum: "537d17eceae35472a435cd54d508c06b1ebd19842172f96b1e777d7fc1f99b81"),
    ]
)
