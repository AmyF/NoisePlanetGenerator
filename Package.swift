// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NoisePlanetGenerator",
    platforms: [
        .macOS(.v15),  // Minimum macOS version
        .iOS(.v18),  // Minimum iOS version
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NoisePlanetGenerator",
            targets: ["NoisePlanetGenerator"])
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NoisePlanetGenerator",
            dependencies: [
                "SharedTypes"
            ]),
        .target(
            name: "SharedTypes",
            publicHeadersPath: "include"
        ),
    ]
)
