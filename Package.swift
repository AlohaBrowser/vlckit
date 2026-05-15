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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha02/vlckit-ios-4.0.0-a16-aloha02-vlckit-ios.zip",
                      checksum: "6ca135cd23eaf16214b9b612162f11792ce74ec0de0d8451a089959212b1fe8a"),
    ]
)
