// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Strict concurrency is pinned explicitly rather than inherited from the
// tools version, so that lowering `swift-tools-version` can never silently
// downgrade the package out of Swift 6 language mode.
let strictConcurrency: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  // SE-0461: nonisolated async functions run on the caller's actor instead of
  // hopping to the global executor. Default in Swift 7.
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  // SE-0470: a conformance declared on a globally-isolated type is inferred
  // isolated instead of being silently treated as nonisolated.
  .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
  name: "Tessera",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "Tessera",
      targets: ["Tessera"]
    )
  ],
  targets: [
    // The executable is one line calling the library. Everything else lives in
    // TesseraKit: a library can be imported by the tests as a module, where an
    // executable target can only be reached through `@testable`, and the split
    // makes the application's own entry point the only public surface there is.
    .executableTarget(
      name: "Tessera",
      dependencies: ["TesseraKit"],
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "TesseraKit",
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "TesseraKitTests",
      dependencies: ["TesseraKit"],
      swiftSettings: strictConcurrency
    ),
  ]
)
