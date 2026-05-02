// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ForgeRuleCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ForgeRuleCore",
            targets: ["ForgeRuleCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/CoderQuinn/ForgeBase.git", from: "0.2.1"),
    ],
    targets: [
        .target(
            name: "libmaxminddb",
            path: "Sources/ForgeRuleCore/GeoMMDB/libmaxminddb",
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
            path: "Sources/ForgeRuleCore/GeoMMDB/GeoMMDBBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ForgeRuleCore",
            dependencies: ["GeoMMDBBridge", "ForgeBase"],
            exclude: [
                "GeoMMDB/GeoMMDBBridge",
                "GeoMMDB/libmaxminddb",
            ]
        ),
        .testTarget(
            name: "ForgeRuleCoreTests",
            dependencies: ["ForgeRuleCore"]
        ),
    ]
)
