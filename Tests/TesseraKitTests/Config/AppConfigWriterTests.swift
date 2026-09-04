import CoreGraphics
import Foundation
import Testing

@testable import TesseraKit

@Suite("AppConfigWriter")
struct AppConfigWriterTests {
  @Test("The defaults survive being written and read back")
  func defaultsRoundTrip() throws {
    #expect(try roundTrip(.default) == AppConfig.default)
  }

  /// Every field, and every one of them away from its default: a key the writer
  /// forgets is a setting that silently goes back to the default the next time the
  /// settings window saves, and only a value that differs from the default can
  /// catch that.
  @Test("A configuration with nothing left at its default survives too")
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
    config.overlayBackground = try OverlayColor(parsing: "#10203040")
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

    #expect(try roundTrip(config) == config)
  }

  @Test("A hotkey nobody wants comes back as no hotkey")
  func disabledHotkeyRoundTrips() throws {
    var config = AppConfig.default
    config.hotkey = nil

    #expect(try roundTrip(config).hotkey == nil)
  }

  @Test("Whole numbers are written the way a person would write them")
  func writesWholeNumbersWithoutADecimalPoint() {
    let toml = AppConfigWriter.toml(for: .default)

    #expect(toml.contains("refresh_interval_seconds = 3\n"))
    #expect(toml.contains("max_windows = 24\n"))
    #expect(toml.contains("refresh_interval_seconds = 3.0\n") == false)
  }

  @Test("A fraction keeps its fraction")
  func keepsFractions() throws {
    var config = AppConfig.default
    config.refreshIntervalSeconds = 2.5

    #expect(AppConfigWriter.toml(for: config).contains("refresh_interval_seconds = 2.5\n"))
    #expect(try roundTrip(config).refreshIntervalSeconds == 2.5)
  }

  @Test("The file says who wrote it and what that costs")
  func explainsItself() {
    let toml = AppConfigWriter.toml(for: .default)

    #expect(toml.hasPrefix("# Tessera configuration."))
    #expect(toml.contains("comments added by hand are not kept"))
  }

  private func roundTrip(_ config: AppConfig) throws -> AppConfig {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesseraTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("config.toml")
    try AppConfigWriter.write(config, to: fileURL)

    return AppConfigLoader(
      configURL: fileURL,
      logger: AppLogger(debugMode: false, category: .config)
    ).load()
  }
}
