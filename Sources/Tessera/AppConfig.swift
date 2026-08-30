import CoreGraphics
import Foundation

struct AppConfig: Equatable {
  var refreshIntervalSeconds: TimeInterval
  var windowThumbnailsStaleSeconds: TimeInterval
  var windowThumbnailTargetSize: CGSize
  var maxWindows: Int
  var closeAfterActivation: Bool
  var showMenuBarIcon: Bool
  var debugMode: Bool
  /// Whether an application may be asked, through Apple Events, to raise a window
  /// that Accessibility cannot reach.
  ///
  /// On by default: without it, Chrome and Finder can only be brought forward, and
  /// which of their windows appears is their choice rather than yours. macOS asks
  /// permission for each application the first time, and a refusal costs nothing —
  /// the switch happens as it would have anyway.
  var usesAppleEvents: Bool
  /// Whether to leave out applications with no Dock icon.
  ///
  /// An application whose activation policy is `.accessory` lives in the menu bar.
  /// Its windows are panels it shows itself, not places to switch to, and
  /// Accessibility often does not list them at all — so a tile for one cannot even
  /// be raised.
  var ignoresMenuBarApplications: Bool
  /// Applications whose windows never appear in the switcher, lowercased.
  ///
  /// A tray application that keeps its window object alive after you close it
  /// looks exactly like a window on another Space — same layer, same title, not on
  /// screen — and no public API tells them apart. Naming the application is the
  /// honest way to leave it out.
  var ignoredApplications: Set<String>
  /// The shortcut that closes the highlighted window from the overlay, or `nil`
  /// when the config turns it off.
  var closeHotkey: HotkeyBinding?
  /// What that shortcut does.
  var closeAction: CloseAction
  /// Whether a preview older than `windowThumbnailsStaleSeconds` is drawn faded.
  var dimsStaleThumbnails: Bool
  /// How many tiles a row may hold before the overlay wraps to the next one.
  var overlayColumns: Int
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
    usesAppleEvents: true,
    ignoresMenuBarApplications: true,
    ignoredApplications: [],
    closeHotkey: HotkeyBinding(modifiers: .command, key: .letterW),
    // Quitting by default: a window closed on an application that stays running is
    // how a leftover window is made, and this switcher has had enough of those.
    closeAction: .quitApplication,
    // Off: a preview a few seconds old is still the window you are looking for,
    // and fading it says more about the switcher than about the window.
    dimsStaleThumbnails: false,
    // Four keeps the panel well inside a laptop screen and the tiles close enough
    // together to take in at a glance.
    overlayColumns: 4,
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
