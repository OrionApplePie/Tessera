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
    .executableTarget(
      name: "Tessera",
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "TesseraTests",
      dependencies: ["Tessera"],
      swiftSettings: strictConcurrency
    ),
  ]
)
