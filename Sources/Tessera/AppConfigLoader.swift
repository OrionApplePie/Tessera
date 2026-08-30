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

    let thumbnailWidth = try positiveDouble(
      values["window_thumbnail_target_width"],
      default: config.windowThumbnailTargetSize.width,
      key: "window_thumbnail_target_width"
    )
    let thumbnailHeight = try positiveDouble(
      values["window_thumbnail_target_height"],
      default: config.windowThumbnailTargetSize.height,
      key: "window_thumbnail_target_height"
    )
    config.windowThumbnailTargetSize = CGSize(width: thumbnailWidth, height: thumbnailHeight)

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
    config.overlayGrouping = try grouping(
      values["overlay_grouping"],
      default: config.overlayGrouping
    )
    config.overlayBackground = try color(
      values["overlay_background"],
      default: config.overlayBackground
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
    config.usesAppleEvents = try bool(
      values["use_apple_events"],
      default: config.usesAppleEvents,
      key: "use_apple_events"
    )
    config.ignoresMenuBarApplications = try bool(
      values["ignore_menu_bar_apps"],
      default: config.ignoresMenuBarApplications,
      key: "ignore_menu_bar_apps"
    )
    config.ignoredApplications = applicationNames(values["ignored_apps"])
    config.closeAfterActivation = try bool(
      values["close_after_activation"],
      default: config.closeAfterActivation,
      key: "close_after_activation"
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
