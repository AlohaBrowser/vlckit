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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha01/vlckit-ios-4.0.0-a16-aloha01-vlckit-ios.zip",
                      checksum: "cc926d753bc2f9052f76595fa2c7b711ec6c791281b5334bb8091ef014929cb7"),
    ]
)
