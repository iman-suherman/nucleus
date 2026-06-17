// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NucleusCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NucleusCore", targets: ["NucleusCore"]),
    ],
    dependencies: [
        .package(path: "../../../"),
    ],
    targets: [
        .target(
            name: "NucleusCore",
            dependencies: [
                .product(name: "NucleusKit", package: "Nucleus"),
                .product(name: "DatabaseKit", package: "Nucleus"),
                .product(name: "AccountKit", package: "Nucleus"),
                .product(name: "MailKit", package: "Nucleus"),
                .product(name: "CalendarKit", package: "Nucleus"),
                .product(name: "NotesKit", package: "Nucleus"),
                .product(name: "SyncKit", package: "Nucleus"),
            ],
            resources: [
                .copy("Resources/DashboardQuotes.json"),
            ],
            linkerSettings: [
                .linkedFramework("Accounts", .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "NucleusCoreTests",
            dependencies: ["NucleusCore"]
        ),
    ]
)
