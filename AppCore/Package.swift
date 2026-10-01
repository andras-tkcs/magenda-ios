// swift-tools-version: 6.0

import PackageDescription

// The app's logic, kept out of the app target so `swift test` runs it on any machine with a Swift
// toolchain, Linux included (ADR 0007). It depends on Foundation at most: no SwiftUI, no UIKit.
let package = Package(
    name: "AppCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "AppCore", targets: ["AppCore"])],
    targets: [
        .target(name: "AppCore", path: "Sources"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"], path: "Tests"),
    ]
)
