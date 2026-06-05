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
                      url: "https://doloto.alohabrowser.com/repository/maven-releases/com/alohamobile/vlckit-ios/4.0.0-a16-aloha19/vlckit-ios-4.0.0-a16-aloha19-vlckit-ios.zip",
                      checksum: "7908ca7ed9db8086af30ba02ceb386d41ada396a19446f8442bcf14a09fe1251"),
    ]
)
