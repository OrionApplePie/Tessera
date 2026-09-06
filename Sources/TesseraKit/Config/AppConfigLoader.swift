import Foundation

struct AppConfigLoader {
  static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/tessera/config.toml")

  let configURL: URL
  private let logger: AppLogger

  init(
    configURL: URL = AppConfigLoader.defaultURL,
    logger: AppLogger = AppLogger(debugMode: true, category: .config)
  ) {
    self.configURL = configURL
    self.logger = logger
  }

  func load() -> AppConfig {
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      logger.info("Config not found at \(configURL.path); using defaults")
      return .default
    }

    do {
      let text = try String(contentsOf: configURL, encoding: .utf8)
      let config = try parse(text)
      logger.info("Loaded config from \(configURL.path)")
      logger.debug("Config debug_mode is \(config.debugMode)")
      return config
    } catch {
      logger.error("Failed to load config at \(configURL.path); using defaults: \(error)")
      return .default
    }
  }

  private func parse(_ text: String) throws -> AppConfig {
    var config = AppConfig.default
    let values = try parseKeyValues(text)

    try applyPreviewSettings(to: &config, from: values)
    try applyOverlaySettings(to: &config, from: values)
    try applyBehaviourSettings(to: &config, from: values)

    return config
  }

  /// What the switcher watches and how it renders a preview.
  private func applyPreviewSettings(
    to config: inout AppConfig,
    from values: [String: String]
  ) throws {
    config.refreshIntervalSeconds = try positiveDouble(
      values["refresh_interval_seconds"],
      default: config.refreshIntervalSeconds,
      key: "refresh_interval_seconds"
    )
    config.windowThumbnailsStaleSeconds = try positiveDouble(
      values["window_thumbnails_stale_seconds"],
      default: config.windowThumbnailsStaleSeconds,
      key: "window_thumbnails_stale_seconds"
    )

    config.capturesLongWindowsWhole = try bool(
      values["window_thumbnail_whole_when_long"],
      default: config.capturesLongWindowsWhole,
      key: "window_thumbnail_whole_when_long"
    )
    config.dimsStaleThumbnails = try bool(
      values["dim_stale_thumbnails"],
      default: config.dimsStaleThumbnails,
      key: "dim_stale_thumbnails"
    )
    config.maxWindows = try positiveInt(
      values["max_windows"],
      default: config.maxWindows,
      key: "max_windows"
    )
  }

  /// How the overlay is laid out and painted.
  private func applyOverlaySettings(
    to config: inout AppConfig,
    from values: [String: String]
  ) throws {
    config.overlayColumns = try positiveInt(
      values["overlay_columns"],
      default: config.overlayColumns,
      key: "overlay_columns"
    )
    config.windowOrder = try windowOrder(values["window_order"], default: config.windowOrder)
    config.usesPrivateSpaceAPI = try bool(
      values["use_private_space_api"],
      default: config.usesPrivateSpaceAPI,
      key: "use_private_space_api"
    )
    config.windowThumbnailMode = try thumbnailMode(
      values["window_thumbnail_mode"],
      default: config.windowThumbnailMode
    )
    try applyTimingSettings(values, into: &config)
    try parseOverlay(values, into: &config)
    config.overlayDeck = try deckStyle(
      values["overlay_deck"],
      default: config.overlayDeck
    )
    config.thumbnailQuality = try quality(
      values["window_thumbnail_quality"],
      default: config.thumbnailQuality
    )
    config.overlayLayout = try layout(
      values["overlay_layout"],
      default: config.overlayLayout
    )
    config.overlayMaxCells = try positiveInt(
      values["overlay_max_cells"],
      default: config.overlayMaxCells,
      key: "overlay_max_cells"
    )

    // A configuration written while the ceiling was a grid says how many rows it
    // wanted. Multiplied out by the row length, it means the same number of Spaces.
    if values["overlay_max_cells"] == nil, values["overlay_rows"] != nil {
      let rows = try positiveInt(values["overlay_rows"], default: 1, key: "overlay_rows")

      config.overlayMaxCells = max(1, rows * max(1, config.overlayColumns))
    }

    config.overlayMinTile = try positiveDouble(
      values["overlay_min_tile"],
      default: config.overlayMinTile,
      key: "overlay_min_tile"
    )
    config.overlayRowAlignment = try rowAlignment(
      values["overlay_row_align"],
      default: config.overlayRowAlignment
    )
    config.overlayArrows = try arrowStep(
      values["overlay_arrows"],
      default: config.overlayArrows
    )
    config.overlaySearch = try search(
      values["overlay_search"],
      default: config.overlaySearch
    )
  }

  /// What the app does, rather than what it shows.
  private func applyBehaviourSettings(
    to config: inout AppConfig,
    from values: [String: String]
  ) throws {
    config.hotkey = try hotkey(values["hotkey"], default: config.hotkey, key: "hotkey")
    config.closeHotkey = try hotkey(
      values["close_hotkey"],
      default: config.closeHotkey,
      key: "close_hotkey"
    )
    config.closeAction = try closeAction(values["close_action"], default: config.closeAction)
    config.ignoresMenuBarApplications = try bool(
      values["ignore_menu_bar_apps"],
      default: config.ignoresMenuBarApplications,
      key: "ignore_menu_bar_apps"
    )
    config.ignoredApplications = applicationNames(values["ignored_apps"])
    config.overlayFillsScreen = try bool(
      values["overlay_fills_screen"],
      default: config.overlayFillsScreen,
      key: "overlay_fills_screen"
    )
    config.showMenuBarIcon = try bool(
      values["show_menu_bar_icon"],
      default: config.showMenuBarIcon,
      key: "show_menu_bar_icon"
    )
    config.debugMode = try bool(
      values["debug_mode"],
      default: config.debugMode,
      key: "debug_mode"
    )
  }

  /// The timings that decide how long the switcher waits for the rest of the
  /// system. Every one of them is a compromise measured on a real desktop rather
  /// than a value with a right answer, which is why they are all here to be changed.
  private func applyTimingSettings(
    _ values: [String: String],
    into config: inout AppConfig
  ) throws {
    config.activationSettleSeconds = try positiveDouble(
      values["activation_settle_seconds"],
      default: config.activationSettleSeconds,
      key: "activation_settle_seconds"
    )
    config.unresponsiveAfterSeconds = try positiveDouble(
      values["unresponsive_after_seconds"],
      default: config.unresponsiveAfterSeconds,
      key: "unresponsive_after_seconds"
    )
  }

  private func parseKeyValues(_ text: String) throws -> [String: String] {
    var values: [String: String] = [:]

    for (lineIndex, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
      let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)

      guard !line.isEmpty else {
        continue
      }

      if line.hasPrefix("[") {
        throw AppConfigError.unsupportedSyntax(line: lineIndex + 1)
      }

      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        throw AppConfigError.invalidLine(line: lineIndex + 1)
      }

      let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
      let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

      guard !key.isEmpty, !value.isEmpty else {
        throw AppConfigError.invalidLine(line: lineIndex + 1)
      }

      values[key] = value
    }

    return values
  }

  /// Drops a trailing comment, but only outside a quoted value: a colour is
  /// spelled `"#2B2E33"`, and a naive split on `#` would eat it.
  private func stripComment(_ line: String) -> String {
    var insideQuotes = false

    for (offset, character) in line.enumerated() {
      if character == "\"" {
        insideQuotes.toggle()
        continue
      }

      if character == "#", !insideQuotes {
        return String(line.prefix(offset))
      }
    }

    return line
  }

}

/// Reading one value out of the file.
///
/// Separate from reading the file itself so that the type stays inside the
/// length the linter allows, and because these two jobs fail differently: a
/// value that does not parse names its own key, while a file that does not parse
/// leaves every default in place.
extension AppConfigLoader {
  private func positiveDouble(
    _ rawValue: String?,
    default defaultValue: Double,
    key: String
  ) throws -> Double {
    guard let rawValue else {
      return defaultValue
    }

    guard let value = Double(rawValue), value > 0 else {
      throw AppConfigError.invalidValue(key: key)
    }

    return value
  }

  private func positiveInt(
    _ rawValue: String?,
    default defaultValue: Int,
    key: String
  ) throws -> Int {
    guard let rawValue else {
      return defaultValue
    }

    guard let value = Int(rawValue), value > 0 else {
      throw AppConfigError.invalidValue(key: key)
    }

    return value
  }

  /// An empty spec disables the hotkey; anything unparsable is an error rather
  /// than a silent fallback, so a typo cannot leave the app with no hotkey at all.
  private func hotkey(
    _ rawValue: String?,
    default defaultValue: HotkeyBinding?,
    key: String
  ) throws -> HotkeyBinding? {
    guard let rawValue else {
      return defaultValue
    }

    let spec = unquoted(rawValue)
    guard !spec.isEmpty else {
      return nil
    }

    do {
      return try HotkeyBinding(parsing: spec)
    } catch {
      logger.error("Invalid \(key) in config: \(error)")
      throw AppConfigError.invalidValue(key: key)
    }
  }

  /// A comma-separated list. Empty means nothing is ignored, which is the default:
  /// leaving a window out of a switcher is the kind of thing to ask for explicitly.
  private func applicationNames(_ rawValue: String?) -> Set<String> {
    guard let rawValue else {
      return []
    }

    let names =
      unquoted(rawValue)
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
      .filter { !$0.isEmpty }

    return Set(names)
  }

  private func closeAction(
    _ rawValue: String?,
    default defaultValue: CloseAction
  ) throws -> CloseAction {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try CloseAction(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid close_action in config: \(error)")
      throw AppConfigError.invalidValue(key: "close_action")
    }
  }

  private func windowOrder(
    _ rawValue: String?,
    default defaultValue: WindowOrder
  ) throws -> WindowOrder {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try WindowOrder(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid window_order in config: \(error)")
      throw AppConfigError.invalidValue(key: "window_order")
    }
  }

  private func thumbnailMode(
    _ rawValue: String?,
    default defaultValue: WindowThumbnailMode
  ) throws -> WindowThumbnailMode {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try WindowThumbnailMode(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid window_thumbnail_mode in config: \(error)")
      throw AppConfigError.invalidValue(key: "window_thumbnail_mode")
    }
  }

  private func grouping(
    _ rawValue: String?,
    default defaultValue: OverlayGrouping
  ) throws -> OverlayGrouping {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlayGrouping(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_grouping in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_grouping")
    }
  }

  private func quality(
    _ rawValue: String?,
    default defaultValue: ThumbnailQuality
  ) throws -> ThumbnailQuality {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try ThumbnailQuality(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid window_thumbnail_quality in config: \(error)")
      throw AppConfigError.invalidValue(key: "window_thumbnail_quality")
    }
  }

  /// The overlay's own keys, in a function of their own: the whole of `parse` is
  /// one assignment after another, and it had outgrown what one function may hold.
  private func parseOverlay(_ values: [String: String], into config: inout AppConfig) throws {
    config.overlayGrouping = try grouping(
      values["overlay_grouping"],
      default: config.overlayGrouping
    )
    config.overlayBackground = try color(
      values["overlay_background"],
      default: config.overlayBackground
    )
  }

  private func search(
    _ rawValue: String?,
    default defaultValue: OverlaySearch
  ) throws -> OverlaySearch {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlaySearch(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_search in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_search")
    }
  }

  private func rowAlignment(
    _ rawValue: String?,
    default defaultValue: OverlayRowAlignment
  ) throws -> OverlayRowAlignment {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlayRowAlignment(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_row_align in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_row_align")
    }
  }

  private func layout(
    _ rawValue: String?,
    default defaultValue: OverlayLayout
  ) throws -> OverlayLayout {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlayLayout(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_layout in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_layout")
    }
  }

  private func arrowStep(
    _ rawValue: String?,
    default defaultValue: OverlayArrowStep
  ) throws -> OverlayArrowStep {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlayArrowStep(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_arrows in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_arrows")
    }
  }

  private func deckStyle(
    _ rawValue: String?,
    default defaultValue: OverlayDeckStyle
  ) throws -> OverlayDeckStyle {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlayDeckStyle(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_deck in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_deck")
    }
  }

  private func color(
    _ rawValue: String?,
    default defaultValue: OverlayColor
  ) throws -> OverlayColor {
    guard let rawValue else {
      return defaultValue
    }

    do {
      return try OverlayColor(parsing: unquoted(rawValue))
    } catch {
      logger.error("Invalid overlay_background in config: \(error)")
      throw AppConfigError.invalidValue(key: "overlay_background")
    }
  }

  /// The TOML subset parsed here keeps values verbatim, quotes included.
  private func unquoted(_ rawValue: String) -> String {
    guard rawValue.count >= 2, rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") else {
      return rawValue
    }

    return String(rawValue.dropFirst().dropLast())
  }

  private func bool(_ rawValue: String?, default defaultValue: Bool, key: String) throws -> Bool {
    guard let rawValue else {
      return defaultValue
    }

    switch rawValue.lowercased() {
    case "true":
      return true
    case "false":
      return false
    default:
      throw AppConfigError.invalidValue(key: key)
    }
  }
}

enum AppConfigError: Error, CustomStringConvertible {
  case invalidLine(line: Int)
  case unsupportedSyntax(line: Int)
  case invalidValue(key: String)

  var description: String {
    switch self {
    case .invalidLine(let line):
      return "invalid TOML line \(line)"
    case .unsupportedSyntax(let line):
      return "unsupported TOML syntax on line \(line)"
    case .invalidValue(let key):
      return "invalid value for \(key)"
    }
  }
}
