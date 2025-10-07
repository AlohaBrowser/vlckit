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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16/vlckit-ios-4.0.0-a16-vlckit-ios.zip",
                      checksum: "31a72756f74bd9fee2fbea170eeb3d4458cfd3bda1271ad1a832eae8036b028a"),
    ]
)

