import Foundation
import Testing

@testable import Tessera

@Suite("AppConfigLoader")
struct AppConfigLoaderTests {
  /// Keys `AppConfigLoader.parse` actually consumes. The shipped example config
  /// is checked against this set so a renamed key cannot go stale unnoticed.
  private static let supportedKeys: Set<String> = [
    "refresh_interval_seconds",
    "window_thumbnails_stale_seconds",
    "window_thumbnail_target_width",
    "window_thumbnail_target_height",
    "max_windows",
    "hotkey",
    "close_hotkey",
    "close_action",
    "use_apple_events",
    "ignore_menu_bar_apps",
    "ignored_apps",
    "dim_stale_thumbnails",
    "overlay_columns",
    "window_order",
    "window_thumbnail_mode",
    "overlay_grouping",
    "overlay_background",
    "close_after_activation",
    "show_menu_bar_icon",
    "debug_mode",
  ]

  @Test("A missing config file leaves every default in place")
  func usesDefaultsWhenTheFileIsMissing() {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesseraTests-\(UUID().uuidString)/config.toml")
    let config = makeLoader(configURL: missing).load()

    expectDefaults(config)
  }

  @Test("Every supported key is read from the file")
  func readsEveryKey() throws {
    try withConfigFile(
      """
      refresh_interval_seconds = 7
      window_thumbnails_stale_seconds = 11
      window_thumbnail_target_width = 320
      window_thumbnail_target_height = 200
      max_windows = 5
      hotkey = "cmd+shift+t"
      close_hotkey = "ctrl+d"
      close_action = "window"
      use_apple_events = false
      ignore_menu_bar_apps = false
      ignored_apps = "AmneziaVPN, Some Tray App"
      dim_stale_thumbnails = true
      overlay_columns = 3
      window_order = "stable"
      window_thumbnail_mode = "corner"
      overlay_grouping = "displays+spaces"
      overlay_background = "#10203040"
      close_after_activation = false
      show_menu_bar_icon = false
      debug_mode = true
      """
    ) { loader in
      let config = loader.load()

      #expect(config.refreshIntervalSeconds == 7)
      #expect(config.windowThumbnailsStaleSeconds == 11)
      #expect(config.windowThumbnailTargetSize.width == 320)
      #expect(config.windowThumbnailTargetSize.height == 200)
      #expect(config.maxWindows == 5)
      #expect(config.hotkey?.displayName == "shift+cmd+t")
      #expect(config.closeHotkey?.displayName == "ctrl+d")
      #expect(config.closeAction == .closeWindow)
      #expect(config.usesAppleEvents == false)
      #expect(config.ignoresMenuBarApplications == false)
      #expect(config.ignoredApplications == ["amneziavpn", "some tray app"])
      #expect(config.dimsStaleThumbnails == true)
      #expect(config.overlayColumns == 3)
      #expect(config.windowOrder == .stable)
      #expect(config.windowThumbnailMode == .corner)
      #expect(config.overlayGrouping == [.displays, .spaces])
      #expect(config.overlayBackground.hexDescription == "#10203040")
      #expect(config.closeAfterActivation == false)
      #expect(config.showMenuBarIcon == false)
      #expect(config.debugMode == true)
    }
  }

  @Test("Keys the file omits keep their default value")
  func keepsDefaultsForOmittedKeys() throws {
    try withConfigFile("max_windows = 4") { loader in
      let config = loader.load()

      #expect(config.maxWindows == 4)
      #expect(config.refreshIntervalSeconds == AppConfig.default.refreshIntervalSeconds)
      #expect(config.closeAfterActivation == AppConfig.default.closeAfterActivation)
    }
  }

  @Test("Comments, trailing comments and blank lines are ignored")
  func ignoresCommentsAndBlankLines() throws {
    try withConfigFile(
      """
      # leading comment

      max_windows = 4  # trailing comment

      # trailing comment block
      """
    ) { loader in
      #expect(loader.load().maxWindows == 4)
    }
  }

  @Test("An unparsable file falls back to defaults instead of half-applying it")
  func fallsBackOnInvalidSyntax() throws {
    let broken = [
      "max_windows",
      "= 4",
      "max_windows =",
      "[preview]\nmax_windows = 4",
    ]

    for contents in broken {
      try withConfigFile(contents) { loader in
        expectDefaults(loader.load())
      }
    }
  }

  @Test("A non-positive number is rejected rather than silently accepted")
  func rejectsNonPositiveNumbers() throws {
    let broken = [
      "refresh_interval_seconds = 0",
      "refresh_interval_seconds = -1",
      "window_thumbnail_target_width = 0",
      "max_windows = 0",
      "overlay_columns = 0",
      "overlay_columns = -1",
      "max_windows = 2.5",
      "max_windows = many",
    ]

    for contents in broken {
      try withConfigFile(contents) { loader in
        expectDefaults(loader.load())
      }
    }
  }

  @Test("An empty hotkey disables it rather than falling back to the default")
  func anEmptyHotkeyDisablesIt() throws {
    try withConfigFile("hotkey = \"\"") { loader in
      let config = loader.load()

      #expect(config.hotkey == nil)
      #expect(config.maxWindows == AppConfig.default.maxWindows)
    }
  }

  @Test("An unparsable hotkey is an error, not a silently ignored line")
  func rejectsAnUnparsableHotkey() throws {
    let broken = [
      "hotkey = \"space\"", "hotkey = \"cmd+nope\"", "hotkey = \"hyper+a\"",
      "close_hotkey = \"nope\"",
      "close_action = \"kill\"",
    ]
    for contents in broken {
      try withConfigFile(contents) { loader in
        expectDefaults(loader.load())
      }
    }
  }

  @Test("A hash inside a quoted value is part of the value, not a comment")
  func doesNotTreatAQuotedHashAsAComment() throws {
    try withConfigFile(
      """
      overlay_background = "#2B2E33"  # the default
      max_windows = 4
      """
    ) { loader in
      let config = loader.load()

      #expect(config.overlayBackground.hexDescription == "#2B2E33FF")
      #expect(config.maxWindows == 4)
    }
  }

  @Test("An ignored application is matched whatever the case")
  func ignoresApplicationsRegardlessOfCase() throws {
    try withConfigFile("ignored_apps = \"AmneziaVPN\"") { loader in
      let config = loader.load()

      #expect(config.ignores(applicationNamed: "AmneziaVPN"))
      #expect(config.ignores(applicationNamed: "amneziavpn"))
      #expect(config.ignores(applicationNamed: "Telegram") == false)
    }
  }

  @Test("An empty or absent list ignores nothing")
  func ignoresNothingByDefault() throws {
    try withConfigFile("ignored_apps = \"\"") { loader in
      #expect(loader.load().ignoredApplications.isEmpty)
    }

    try withConfigFile("max_windows = 4") { loader in
      #expect(loader.load().ignores(applicationNamed: "AmneziaVPN") == false)
    }
  }

  @Test("Stray separators and spacing in the list are tolerated")
  func toleratesUntidyLists() throws {
    try withConfigFile("ignored_apps = \"  Alpha ,, Beta  ,\"") { loader in
      #expect(loader.load().ignoredApplications == ["alpha", "beta"])
    }
  }

  @Test("A window order nobody offers is an error")
  func rejectsAnUnknownWindowOrder() throws {
    try withConfigFile("window_order = \"recent\"") { loader in
      expectDefaults(loader.load())
    }
  }

  @Test("A grouping that is not one of the two is an error")
  func rejectsAnUnknownGrouping() throws {
    try withConfigFile("overlay_grouping = \"by-app\"") { loader in
      expectDefaults(loader.load())
    }
  }

  @Test("A colour that is not hex is an error rather than a quiet default")
  func rejectsAnUnparsableColour() throws {
    for contents in ["overlay_background = \"nope\"", "overlay_background = \"#FFF\""] {
      try withConfigFile(contents) { loader in
        expectDefaults(loader.load())
      }
    }
  }

  @Test("A flag that is not true or false is rejected")
  func rejectsNonBooleanFlags() throws {
    for contents in ["debug_mode = yes", "debug_mode = 1", "dim_stale_thumbnails = 1"] {
      try withConfigFile(contents) { loader in
        expectDefaults(loader.load())
      }
    }
  }

  @Test("TRUE and False are accepted regardless of case")
  func acceptsBooleansInAnyCase() throws {
    try withConfigFile("debug_mode = TRUE\nshow_menu_bar_icon = False") { loader in
      let config = loader.load()

      #expect(config.debugMode == true)
      #expect(config.showMenuBarIcon == false)
    }
  }

  @Test("The shipped example config mentions exactly the keys the loader reads")
  func exampleConfigMatchesTheLoader() throws {
    let exampleURL = Self.repositoryRoot.appendingPathComponent("config.example.toml")
    let contents = try String(contentsOf: exampleURL, encoding: .utf8)

    let keys =
      contents
      .split(whereSeparator: \.isNewline)
      .map { line -> Substring in
        line.prefix { $0 != "#" }
      }
      .compactMap { line -> String? in
        guard let separator = line.firstIndex(of: "=") else {
          return nil
        }

        return String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      }

    #expect(Set(keys) == Self.supportedKeys)
    #expect(keys.count == Self.supportedKeys.count, "the example config repeats a key")
  }

  @Test("The example config documents the built-in defaults")
  func exampleConfigDocumentsTheDefaults() throws {
    let exampleURL = Self.repositoryRoot.appendingPathComponent("config.example.toml")
    let config = makeLoader(configURL: exampleURL).load()

    expectDefaults(config)
  }
}

extension AppConfigLoaderTests {
  // MARK: - Helpers

  private static let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()  // TesseraTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root

  private func makeLoader(configURL: URL) -> AppConfigLoader {
    AppConfigLoader(configURL: configURL, logger: AppLogger(debugMode: false, category: .config))
  }

  private func withConfigFile(
    _ contents: String,
    _ body: (AppConfigLoader) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesseraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config.toml")
    try contents.write(to: configURL, atomically: true, encoding: .utf8)

    try body(makeLoader(configURL: configURL))
  }

  private func expectDefaults(
    _ config: AppConfig,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let defaults = AppConfig.default

    #expect(
      config.refreshIntervalSeconds == defaults.refreshIntervalSeconds,
      sourceLocation: sourceLocation
    )
    #expect(
      config.windowThumbnailsStaleSeconds == defaults.windowThumbnailsStaleSeconds,
      sourceLocation: sourceLocation
    )
    #expect(
      config.windowThumbnailTargetSize == defaults.windowThumbnailTargetSize,
      sourceLocation: sourceLocation
    )
    #expect(config.maxWindows == defaults.maxWindows, sourceLocation: sourceLocation)
    #expect(
      config.closeAfterActivation == defaults.closeAfterActivation,
      sourceLocation: sourceLocation
    )
    #expect(config.showMenuBarIcon == defaults.showMenuBarIcon, sourceLocation: sourceLocation)
    #expect(config.debugMode == defaults.debugMode, sourceLocation: sourceLocation)
    #expect(config.hotkey == defaults.hotkey, sourceLocation: sourceLocation)
    #expect(config.closeHotkey == defaults.closeHotkey, sourceLocation: sourceLocation)
    #expect(config.closeAction == defaults.closeAction, sourceLocation: sourceLocation)
    #expect(config.usesAppleEvents == defaults.usesAppleEvents, sourceLocation: sourceLocation)
    #expect(
      config.ignoresMenuBarApplications == defaults.ignoresMenuBarApplications,
      sourceLocation: sourceLocation
    )
    #expect(
      config.ignoredApplications == defaults.ignoredApplications,
      sourceLocation: sourceLocation
    )
    #expect(
      config.dimsStaleThumbnails == defaults.dimsStaleThumbnails,
      sourceLocation: sourceLocation
    )
    #expect(config.overlayColumns == defaults.overlayColumns, sourceLocation: sourceLocation)
    #expect(config.windowOrder == defaults.windowOrder, sourceLocation: sourceLocation)
    #expect(
      config.overlayGrouping == defaults.overlayGrouping,
      sourceLocation: sourceLocation
    )
    #expect(
      config.overlayBackground == defaults.overlayBackground,
      sourceLocation: sourceLocation
    )
  }

}
