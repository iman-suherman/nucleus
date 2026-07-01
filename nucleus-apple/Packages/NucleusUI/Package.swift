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
        .package(path: "../../../"),
    ],
    targets: [
        .target(
            name: "NucleusUI",
            dependencies: [
                .product(name: "NucleusCore", package: "NucleusCore"),
                .product(name: "CalendarKit", package: "Nucleus"),
                .product(name: "NucleusKit", package: "Nucleus"),
            ]
        ),
    ]
)
