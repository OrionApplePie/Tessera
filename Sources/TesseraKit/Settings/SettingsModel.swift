import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// The settings window's editable copy of the configuration.
///
/// Text fields hold text, not parsed values: a hotkey being typed passes through
/// states that are not yet a hotkey, and refusing to let someone type is worse
/// than telling them at the end what did not parse.
@MainActor
final class SettingsModel: ObservableObject {
  // The values below are placeholders, overwritten by `apply` before the window is
  // ever shown. What Tessera actually ships with lives in `AppConfig.default` and
  // nowhere else, so that a second copy cannot drift from it.
  @Published var hotkey = ""
  @Published var closeHotkey = ""
  @Published var ignoredApplications = ""
  @Published var background = Color.black

  @Published var overlayColumns: Int = 0
  @Published var overlayMaxCells: Int = 0
  @Published var overlayMinTile: Double = 0
  @Published var windowOrder = WindowOrder.title
  @Published var thumbnailMode = WindowThumbnailMode.fit
  @Published var thumbnailQuality = ThumbnailQuality.tile
  @Published var overlayLayout = OverlayLayout.flow
  @Published var overlayRowAlignment = OverlayRowAlignment.center
  @Published var overlayDeck = OverlayDeckStyle.stack
  @Published var overlayArrows = OverlayArrowStep.spaces
  @Published var overlaySearch = OverlaySearch.letter
  @Published var closeAction = CloseAction.closeWindow
  @Published var ignoresMenuBarApplications = false
  @Published var usesPrivateSpaceAPI = false
  @Published var activationSettleSeconds: Double = 0
  @Published var unresponsiveAfterSeconds: Double = 0
  @Published var groupsDisplays = false
  @Published var groupsSpaces = false

  @Published var refreshIntervalSeconds: Double = 0
  @Published var windowThumbnailsStaleSeconds: Double = 0
  @Published var capturesLongWindowsWhole = false
  @Published var dimsStaleThumbnails = false
  @Published var overlayFillsScreen = false
  @Published var maxWindows: Int = 0

  @Published var closeAfterActivation = false
  @Published var showMenuBarIcon = false
  @Published var debugMode = false

  @Published private(set) var problem: String?

  init(config: AppConfig) {
    apply(config)
  }

  /// Fills the form from a configuration.
  ///
  /// One mapping, used both to open the window and to put the defaults back, so
  /// that a setting added to one is never missing from the other.
  private func apply(_ config: AppConfig) {
    hotkey = config.hotkey?.displayName ?? ""
    closeHotkey = config.closeHotkey?.displayName ?? ""
    ignoredApplications = config.ignoredApplications.sorted().joined(separator: ", ")
    background = Color(config.overlayBackground)
    overlayColumns = config.overlayColumns
    overlayMaxCells = config.overlayMaxCells
    overlayMinTile = config.overlayMinTile
    windowOrder = config.windowOrder
    thumbnailMode = config.windowThumbnailMode
    thumbnailQuality = config.thumbnailQuality
    overlayLayout = config.overlayLayout
    overlayRowAlignment = config.overlayRowAlignment
    overlayDeck = config.overlayDeck
    overlayArrows = config.overlayArrows
    overlaySearch = config.overlaySearch
    closeAction = config.closeAction
    ignoresMenuBarApplications = config.ignoresMenuBarApplications
    usesPrivateSpaceAPI = config.usesPrivateSpaceAPI
    activationSettleSeconds = config.activationSettleSeconds
    unresponsiveAfterSeconds = config.unresponsiveAfterSeconds
    groupsDisplays = config.overlayGrouping.contains(.displays)
    groupsSpaces = config.overlayGrouping.contains(.spaces)
    refreshIntervalSeconds = config.refreshIntervalSeconds
    windowThumbnailsStaleSeconds = config.windowThumbnailsStaleSeconds
    capturesLongWindowsWhole = config.capturesLongWindowsWhole
    dimsStaleThumbnails = config.dimsStaleThumbnails
    overlayFillsScreen = config.overlayFillsScreen
    maxWindows = config.maxWindows
    closeAfterActivation = config.closeAfterActivation
    showMenuBarIcon = config.showMenuBarIcon
    debugMode = config.debugMode
  }

  /// Puts every field back to what Tessera ships with.
  ///
  /// Only the form: nothing is written until the window is saved, so this can be
  /// undone by cancelling, and what the defaults actually are can be read off the
  /// pages before committing to them.
  func restoreDefaults() {
    apply(.default)
    problem = nil
  }

  /// The configuration as edited, or `nil` with `problem` set to what is wrong.
  func makeConfig() -> AppConfig? {
    problem = nil

    var config = AppConfig.default

    do {
      config.hotkey = try binding(hotkey)
      config.closeHotkey = try binding(closeHotkey)
    } catch {
      problem = "\(error)"
      return nil
    }

    config.overlayBackground = OverlayColor(background)
    config.ignoredApplications = Set(
      ignoredApplications
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
    )

    var grouping: OverlayGrouping = []
    if groupsDisplays {
      grouping.insert(.displays)
    }
    if groupsSpaces {
      grouping.insert(.spaces)
    }
    config.overlayGrouping = grouping

    config.overlayColumns = max(1, overlayColumns)
    config.overlayMaxCells = max(1, overlayMaxCells)
    config.overlayMinTile = max(60, overlayMinTile)
    config.windowOrder = windowOrder
    config.windowThumbnailMode = thumbnailMode
    config.activationSettleSeconds = activationSettleSeconds
    config.unresponsiveAfterSeconds = unresponsiveAfterSeconds
    config.refreshIntervalSeconds = max(0.5, refreshIntervalSeconds)
    config.windowThumbnailsStaleSeconds = max(1, windowThumbnailsStaleSeconds)
    config.capturesLongWindowsWhole = capturesLongWindowsWhole
    config.dimsStaleThumbnails = dimsStaleThumbnails
    config.thumbnailQuality = thumbnailQuality
    config.overlayLayout = overlayLayout
    config.overlayRowAlignment = overlayRowAlignment
    config.overlayDeck = overlayDeck
    config.overlayArrows = overlayArrows
    config.overlaySearch = overlaySearch
    config.closeAction = closeAction
    config.ignoresMenuBarApplications = ignoresMenuBarApplications
    config.usesPrivateSpaceAPI = usesPrivateSpaceAPI
    config.overlayFillsScreen = overlayFillsScreen
    config.maxWindows = max(1, maxWindows)
    config.closeAfterActivation = closeAfterActivation
    config.showMenuBarIcon = showMenuBarIcon
    config.debugMode = debugMode

    return config
  }

  /// A shortcut field as typed, or nothing at all when it is empty — a shortcut
  /// someone turned off rather than one that failed to parse.
  private func binding(_ text: String) throws -> HotkeyBinding? {
    let spec = text.trimmingCharacters(in: .whitespaces)

    guard !spec.isEmpty else {
      return nil
    }

    return try HotkeyBinding(parsing: spec)
  }
}

extension OverlayColor {
  /// SwiftUI hands back a `Color` in whatever space the picker used; the config
  /// stores sRGB components, so it is converted rather than assumed.
  init(_ color: Color) {
    let converted = NSColor(color).usingColorSpace(.sRGB)

    self.init(
      red: Double(converted?.redComponent ?? 0),
      green: Double(converted?.greenComponent ?? 0),
      blue: Double(converted?.blueComponent ?? 0),
      alpha: Double(converted?.alphaComponent ?? 1)
    )
  }
}
