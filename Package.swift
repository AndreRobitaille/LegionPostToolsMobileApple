// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddyCheckCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "BuddyCheckCore", targets: ["BuddyCheckCore"]),
               .library(name: "BuddyCheckContacts", targets: ["BuddyCheckContacts"]),
               .library(name: "BuddyCheckAPI", targets: ["BuddyCheckAPI"])],
    targets: [
        .target(name: "BuddyCheckCore"),
        .target(name: "BuddyCheckContacts", dependencies: ["BuddyCheckCore"]),
        .target(name: "BuddyCheckAPI", dependencies: ["BuddyCheckCore"]),
        .testTarget(name: "BuddyCheckAPITests", dependencies: ["BuddyCheckAPI"]),
        .testTarget(name: "BuddyCheckContactsTests", dependencies: ["BuddyCheckContacts", "BuddyCheckCore"]),
        .testTarget(name: "BuddyCheckCoreTests", dependencies: ["BuddyCheckCore"])
    ]
)
