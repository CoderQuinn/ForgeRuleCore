// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ForgeFlowClassifier",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ForgeFlowClassifier",
            targets: ["ForgeFlowClassifier"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/CoderQuinn/ForgeBase.git", from: "0.2.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "libmaxminddb",
            path: "Sources/ForgeFlowClassifier/GeoMMDB/libmaxminddb",
            sources: [
                "src/data-pool.c",
                "src/maxminddb.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("MMDB_UINT128_IS_BYTE_ARRAY"),
                .define("PACKAGE_VERSION", to: "\"0.1.0\""),
                .headerSearchPath("src"),
            ]
        ),
        .target(
            name: "GeoMMDBBridge",
            dependencies: ["libmaxminddb"],
            path: "Sources/ForgeFlowClassifier/GeoMMDB/GeoMMDBBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ForgeFlowClassifier",
            dependencies: ["GeoMMDBBridge", "ForgeBase"],
            exclude: [
                "GeoMMDB/GeoMMDBBridge",
                "GeoMMDB/libmaxminddb",
            ]
        ),
        .testTarget(
            name: "ForgeFlowClassifierTests",
            dependencies: ["ForgeFlowClassifier"]
        ),
    ]
)
