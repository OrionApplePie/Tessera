import CoreGraphics
import Foundation

struct AppConfig {
  var refreshIntervalSeconds: TimeInterval
  var windowThumbnailsStaleSeconds: TimeInterval
  var windowThumbnailTargetSize: CGSize
  var maxWindows: Int
  var closeAfterActivation: Bool
  var showMenuBarIcon: Bool
  var debugMode: Bool
  /// Applications whose windows never appear in the switcher, lowercased.
  ///
  /// A tray application that keeps its window object alive after you close it
  /// looks exactly like a window on another Space — same layer, same title, not on
  /// screen — and no public API tells them apart. Naming the application is the
  /// honest way to leave it out.
  var ignoredApplications: Set<String>
  /// What decides the order of the tiles inside a group.
  var windowOrder: WindowOrder
  /// Whether the overlay splits its tiles into per-Space groups.
  var overlayGrouping: OverlayGrouping
  /// The overlay's own surface. Opaque by default; give it an alpha channel to
  /// let the desktop back through.
  var overlayBackground: OverlayColor
  /// The global hotkey that toggles the overlay, or `nil` when the config
  /// disables it and triggering is left to the CLI.
  var hotkey: HotkeyBinding?

  func ignores(applicationNamed name: String) -> Bool {
    ignoredApplications.contains(name.lowercased())
  }

  static let `default` = AppConfig(
    refreshIntervalSeconds: 3,
    windowThumbnailsStaleSeconds: 30,
    windowThumbnailTargetSize: CGSize(width: 240, height: 160),
    maxWindows: 24,
    closeAfterActivation: true,
    showMenuBarIcon: true,
    debugMode: false,
    // Displays are worth telling apart out of the box; Spaces are not, until
    // someone asks for them.
    ignoredApplications: [],
    windowOrder: .title,
    overlayGrouping: .displays,
    // Matte graphite: dark enough for white tile text, light enough not to read as
    // a hole in the screen.
    overlayBackground: OverlayColor(red: 43 / 255, green: 46 / 255, blue: 51 / 255),
    // Deliberately not cmd- or alt+space: those belong to Spotlight and to every
    // launcher that replaces it.
    hotkey: HotkeyBinding(modifiers: [.control, .option], key: .space)
  )
}
