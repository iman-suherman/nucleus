// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nucleus",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "NucleusKit", targets: ["NucleusKit"]),
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
        .library(name: "AccountKit", targets: ["AccountKit"]),
        .library(name: "MailKit", targets: ["MailKit"]),
        .library(name: "CalendarKit", targets: ["CalendarKit"]),
        .library(name: "ClipboardKit", targets: ["ClipboardKit"]),
        .library(name: "NotesKit", targets: ["NotesKit"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
    ],
    targets: [
        .target(name: "NucleusKit"),
        .testTarget(name: "NucleusKitTests", dependencies: ["NucleusKit"]),
        .target(
            name: "DatabaseKit",
            dependencies: ["NucleusKit"]
        ),
        .testTarget(name: "DatabaseKitTests", dependencies: ["DatabaseKit"]),
        .target(
            name: "AccountKit",
            dependencies: ["NucleusKit", "DatabaseKit"]
        ),
        .target(
            name: "MailKit",
            dependencies: ["NucleusKit", "DatabaseKit", "AccountKit"]
        ),
        .testTarget(name: "MailKitTests", dependencies: ["MailKit"]),
        .target(
            name: "CalendarKit",
            dependencies: ["NucleusKit", "DatabaseKit", "AccountKit"]
        ),
        .testTarget(name: "CalendarKitTests", dependencies: ["CalendarKit"]),
        .target(
            name: "ClipboardKit",
            dependencies: ["NucleusKit", "DatabaseKit"]
        ),
        .testTarget(name: "ClipboardKitTests", dependencies: ["ClipboardKit"]),
        .target(
            name: "NotesKit",
            dependencies: ["NucleusKit", "DatabaseKit", "AccountKit"]
        ),
        .target(
            name: "SyncKit",
            dependencies: ["NucleusKit", "DatabaseKit"]
        ),
    ]
)
