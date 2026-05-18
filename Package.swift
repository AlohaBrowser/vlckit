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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha06/vlckit-ios-4.0.0-a16-aloha06-vlckit-ios.zip",
                      checksum: "72aca4f379ca696013565e3d4a1e8f7300de8bcca78eaee3c9ae3f59378d4299"),
    ]
)
