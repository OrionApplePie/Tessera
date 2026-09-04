import CoreGraphics
import Foundation
import Testing

@testable import TesseraKit

@Suite("SettingsModel")
struct SettingsModelTests {
  /// The settings window builds its configuration from `AppConfig.default` and then
  /// sets what it holds, so a key the model does not carry is not merely missing
  /// from the window — it goes back to its default the moment anything else is
  /// saved. Every field has to survive the trip through the model.
  @Test("A configuration survives a trip through the settings window")
  @MainActor
  func customisedConfigurationRoundTrips() throws {
    var config = AppConfig.default
    config.refreshIntervalSeconds = 7.5
    config.windowThumbnailsStaleSeconds = 11
    config.dimsStaleThumbnails = true
    config.maxWindows = 9
    config.overlayColumns = 6
    config.overlayMaxCells = 14
    config.overlayMinTile = 210
    config.windowOrder = .stable
    config.overlayGrouping = [.displays, .spaces]
    config.hotkey = try HotkeyBinding(parsing: "cmd+shift+t")
    config.closeHotkey = try HotkeyBinding(parsing: "ctrl+shift+q")
    config.closeAction = .closeWindow
    config.ignoredApplications = ["amneziavpn", "some tray app"]
    config.ignoresMenuBarApplications = false
    config.usesPrivateSpaceAPI = false
    config.windowThumbnailMode = .threeQuarters
    config.thumbnailQuality = .hd
    config.overlayDeck = .fan
    config.overlayArrows = .windows
    config.overlaySearch = .fuzzy
    config.overlayLayout = .flow
    config.overlayRowAlignment = .trailing
    config.overlayFillsScreen = true
    config.activationSettleSeconds = 0.75
    config.unresponsiveAfterSeconds = 4
    config.closeAfterActivation = false
    config.showMenuBarIcon = false
    config.debugMode = true

    let edited = SettingsModel(config: config).makeConfig()

    // The colour is the one field that cannot be compared: it goes out through
    // SwiftUI's `Color` and comes back through AppKit's sRGB conversion, which is
    // floating point either way. That it is carried at all is `OverlayColorTests`'
    // business.
    var restored = edited
    restored?.overlayBackground = config.overlayBackground

    #expect(restored == config)
  }

  /// A hotkey field is text while it is being typed, and empty text is a shortcut
  /// somebody turned off rather than one that failed to parse.
  @Test("An empty shortcut field turns the shortcut off")
  @MainActor
  func emptyShortcutFieldsDisableTheShortcuts() {
    var config = AppConfig.default
    config.hotkey = nil
    config.closeHotkey = nil

    let model = SettingsModel(config: config)
    let edited = model.makeConfig()

    #expect(edited?.hotkey == nil)
    #expect(edited?.closeHotkey == nil)
    #expect(model.problem == nil)
  }

  /// What cannot be parsed is reported rather than dropped: a shortcut silently
  /// reset to its default is a shortcut that stops working for no visible reason.
  @Test("A shortcut that does not parse is refused with a reason")
  @MainActor
  func refusesAShortcutThatDoesNotParse() {
    let model = SettingsModel(config: .default)
    model.closeHotkey = "cmd+nonsense"

    #expect(model.makeConfig() == nil)
    #expect(model.problem != nil)
  }
}
