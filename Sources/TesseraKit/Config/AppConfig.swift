import CoreGraphics
import Foundation

struct AppConfig: Equatable {
  var refreshIntervalSeconds: TimeInterval
  var windowThumbnailsStaleSeconds: TimeInterval
  var maxWindows: Int
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
  /// Whether the window server may be asked directly which Space a window is on.
  ///
  /// That question has no public answer, so this is the one private interface here.
  /// Switched off — or broken by an update — Space membership goes back to being
  /// inferred from what appears on screen together, which is what it always was.
  var usesPrivateSpaceAPI: Bool
  /// What a tile shows of a window: the whole of it, or its corner at full size.
  var windowThumbnailMode: WindowThumbnailMode
  /// How many pixels a thumbnail is captured with.
  var thumbnailQuality: ThumbnailQuality
  /// Whether a window much longer than the tile it is drawn in is captured whole,
  /// whatever `windowThumbnailMode` says. A crop of one shows its top and nothing
  /// that tells it apart.
  var capturesLongWindowsWhole: Bool
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
  var overlayDeck: OverlayDeckStyle
  /// What an arrow counts in: Spaces, or the windows inside them.
  var overlayArrows: OverlayArrowStep
  /// What typing at the map does: walk the windows of one letter, or build a query.
  var overlaySearch: OverlaySearch
  /// How the Spaces are arranged on the map.
  var overlayLayout: OverlayLayout
  /// Where a short row sits under a long one.
  var overlayRowAlignment: OverlayRowAlignment
  /// The most cells the map draws, shared out between the displays. A cell is what
  /// stands beside its neighbour: a Space when its windows are stacked, a window
  /// when they are fanned out. This is a ceiling and nothing else — the shape of
  /// the map is the layout's business, and only the fixed layout is told a row
  /// length.
  var overlayMaxCells: Int
  /// The smallest a tile may be drawn. A map that keeps every Space by making each
  /// one too small to recognise has answered the wrong question, so the count comes
  /// down instead: what will not fit at this size is left off.
  var overlayMinTile: CGFloat
  /// Whether the overlay takes the screen it opens on, less a margin, and draws
  /// its tiles as large as that room allows.
  var overlayFillsScreen: Bool
  /// The global hotkey that toggles the overlay, or `nil` when the config
  /// disables it and triggering is left to the CLI.
  var hotkey: HotkeyBinding?

  func ignores(applicationNamed name: String) -> Bool {
    ignoredApplications.contains(name.lowercased())
  }

  static let `default` = AppConfig(
    refreshIntervalSeconds: 3,
    windowThumbnailsStaleSeconds: 30,
    maxWindows: 24,
    showMenuBarIcon: true,
    debugMode: false,
    ignoresMenuBarApplications: false,
    ignoredApplications: [],
    closeHotkey: HotkeyBinding(modifiers: .command, key: .letterW),
    // Quitting by default: a window closed on an application that stays running is
    // how a leftover window is made, and this switcher has had enough of those.
    closeAction: .quitApplication,
    // On: a preview taken a while ago is worth marking as such, because a window
    // that has moved on since looks like the window you want and is not.
    dimsStaleThumbnails: true,
    // Only the fixed arrangement is told a row length; seven is what a laptop
    // screen carries at a readable tile.
    overlayColumns: 7,
    windowOrder: .title,
    usesPrivateSpaceAPI: true,
    // Three quarters of the window rather than all of it: the part that says which
    // window this is — the top of a page, the first lines of a document — at a size
    // that can still be read, instead of the whole thing shrunk past legibility.
    windowThumbnailMode: .threeQuarters,
    // Captured sharper than the tile strictly needs, so a preview still reads when
    // the overlay grows into a large screen.
    thumbnailQuality: .hd,
    // A tall narrow window — a chat panel, a player — is recognised by its shape,
    // and a square crop of one throws that away.
    capturesLongWindowsWhole: true,
    // Long enough for a Space switch and its animation to finish, so a window is
    // not condemned for being slow. Nothing is polled while it passes: the system
    // announces the switch, and this is only the point at which waiting stops.
    activationSettleSeconds: 1.5,
    // A capture normally answers in well under 200ms and an Accessibility question
    // in a few; measured against a normal desktop, half a second was not enough for
    // either and two is. Anything past that is wedged, not slow.
    unresponsiveAfterSeconds: 2,
    overlayGrouping: [.displays, .spaces],
    // Matte graphite: dark enough for white tile text, light enough not to read as
    // a hole in the screen.
    overlayBackground: OverlayColor(
      red: 43 / 255, green: 46 / 255, blue: 51 / 255, alpha: 194 / 255),
    overlayDeck: .stack,
    overlayArrows: .spaces,
    overlaySearch: .letter,
    overlayLayout: .flow,
    overlayRowAlignment: .leading,
    overlayMaxCells: 24,
    overlayMinTile: 150,
    overlayFillsScreen: true,
    // Deliberately not cmd- or alt+space: those belong to Spotlight and to every
    // launcher that replaces it.
    hotkey: HotkeyBinding(modifiers: [.control, .option], key: .space)
  )
}
