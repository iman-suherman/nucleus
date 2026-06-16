// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NucleusUI",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "NucleusUI", targets: ["NucleusUI"]),
    ],
    dependencies: [
        .package(path: "../NucleusCore"),
    ],
    targets: [
        .target(
            name: "NucleusUI",
            dependencies: [
                .product(name: "NucleusCore", package: "NucleusCore"),
            ]
        ),
    ]
)
