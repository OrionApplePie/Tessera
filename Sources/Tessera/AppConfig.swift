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
  /// What a tile shows of a window: the whole of it, or its corner at full size.
  var windowThumbnailMode: WindowThumbnailMode
  /// How long the system is given to finish a switch — a Space to change, an
  /// application to come forward — before a window that has not appeared is one
  /// that is not coming.
  var activationSettleSeconds: Double
  /// How long anything — a window asked for a preview, an application asked an
  /// Accessibility question — may go without answering before it is treated as
  /// wedged rather than busy.
  var unresponsiveAfterSeconds: Double
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
    // The whole window. A corner reads better for text, but only once someone has
    // decided that is what they want to see.
    windowThumbnailMode: .fit,
    // Long enough for a Space switch and its animation to finish, so a window is
    // not condemned for being slow. Nothing is polled while it passes: the system
    // announces the switch, and this is only the point at which waiting stops.
    activationSettleSeconds: 1.5,
    // A capture normally answers in well under 200ms and an Accessibility question
    // in a few; measured against a normal desktop, half a second was not enough for
    // either and two is. Anything past that is wedged, not slow.
    unresponsiveAfterSeconds: 2,
    overlayGrouping: .displays,
    // Matte graphite: dark enough for white tile text, light enough not to read as
    // a hole in the screen.
    overlayBackground: OverlayColor(red: 43 / 255, green: 46 / 255, blue: 51 / 255),
    // Deliberately not cmd- or alt+space: those belong to Spotlight and to every
    // launcher that replaces it.
    hotkey: HotkeyBinding(modifiers: [.control, .option], key: .space)
  )
}
