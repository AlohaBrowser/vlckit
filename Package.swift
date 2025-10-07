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
                      url: "https://download.videolan.org/cocoapods/unstable/VLCKit-4.0.0a16-95efb67d-8e3d17c89.tar.xz",
                      checksum: "e26c8b1bb65c3cd413a2b3911687e28092da05edb09244303b5da63dbee4bd20"),
    ]
)