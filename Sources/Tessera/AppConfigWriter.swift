import CoreGraphics
import Foundation

/// Turns a configuration back into the file it was read from.
///
/// The file is regenerated whole rather than edited in place: this parser reads a
/// subset of TOML and has no notion of where a value sat or what was written
/// around it. Anything a person added by hand — their own comments, their own
/// ordering — is lost when the settings window saves. That is the price of a
/// settings window over a text file, and it is worth saying out loud.
enum AppConfigWriter {
  static func toml(for config: AppConfig) -> String {
    let sections = [
      header,
      previewSection(config),
      overlaySection(config),
      behaviourSection(config),
      timingSection(config),
    ]

    return sections.joined(separator: "\n\n") + "\n"
  }

  static func write(_ config: AppConfig, to fileURL: URL) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try toml(for: config).write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private static let header = """
    # Tessera configuration.
    # Written by the settings window; comments added by hand are not kept.
    """

  private static func previewSection(_ config: AppConfig) -> String {
    """
    refresh_interval_seconds = \(number(config.refreshIntervalSeconds))
    window_thumbnails_stale_seconds = \(number(config.windowThumbnailsStaleSeconds))

    # Fade a preview once it is older than window_thumbnails_stale_seconds.
    dim_stale_thumbnails = \(config.dimsStaleThumbnails)

    window_thumbnail_target_width = \(number(config.windowThumbnailTargetSize.width))
    window_thumbnail_target_height = \(number(config.windowThumbnailTargetSize.height))
    max_windows = \(config.maxWindows)
    """
  }

  private static func overlaySection(_ config: AppConfig) -> String {
    """
    # How many tiles a row may hold before the overlay wraps to the next row.
    overlay_columns = \(config.overlayColumns)

    # Tile order inside a group: "title", "application" or "stable".
    window_order = "\(config.windowOrder.name)"

    # Ask the window server directly which Space a window is on. There is no public
    # way to ask, so this is the one private interface here; off, Space membership
    # is inferred from what appears on screen together.
    use_private_space_api = \(config.usesPrivateSpaceAPI)

    # What a tile shows: "fit" for the whole window, or its top left corner at
    # "corner" (1:1), "corner2x" (twice as much) or "quarter" (about a quarter of
    # the window).
    window_thumbnail_mode = "\(config.windowThumbnailMode.name)"
    overlay_deck = "\(config.overlayDeck.name)"

    # Tile grouping: "displays", "spaces", "displays+spaces" or "none".
    overlay_grouping = "\(config.overlayGrouping.name)"

    # Overlay surface, #RRGGBB or #RRGGBBAA.
    overlay_background = "\(config.overlayBackground.hexDescription)"
    """
  }

  private static func behaviourSection(_ config: AppConfig) -> String {
    """
    # Global hotkey that toggles the overlay. "" turns it off.
    hotkey = "\(config.hotkey?.displayName ?? "")"

    # Leave out applications with no Dock icon, the ones that live in the menu bar.
    ignore_menu_bar_apps = \(config.ignoresMenuBarApplications)

    # Applications to leave out of the switcher, comma separated.
    ignored_apps = "\(config.ignoredApplications.sorted().joined(separator: ", "))"

    close_after_activation = \(config.closeAfterActivation)
    show_menu_bar_icon = \(config.showMenuBarIcon)
    debug_mode = \(config.debugMode)
    """
  }

  /// Whole numbers are written without a decimal point, the way a person would.
  /// How long the switcher waits for the rest of the system. Every one of these is
  /// a compromise measured on a real desktop, not a value with a right answer.
  private static func timingSection(_ config: AppConfig) -> String {
    """
    # How long the system is given to finish a switch before a window that has not
    # appeared is taken to be one that is not coming. Nothing is polled while it
    # passes: a Space change and an application coming forward are both announced.
    activation_settle_seconds = \(number(config.activationSettleSeconds))

    # How long anything may go without answering before it is treated as wedged
    # rather than busy: a window asked for a preview, an application asked an
    # Accessibility question.
    unresponsive_after_seconds = \(number(config.unresponsiveAfterSeconds))
    """
  }

  private static func number(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15
      ? String(Int(value)) : String(value)
  }
}
