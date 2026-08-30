import CoreGraphics
import Foundation
import Testing

@testable import Tessera

@Suite("AppConfigWriter")
struct AppConfigWriterTests {
  @Test("The defaults survive being written and read back")
  func defaultsRoundTrip() throws {
    #expect(try roundTrip(.default) == AppConfig.default)
  }

  @Test("A configuration with nothing left at its default survives too")
  func customisedConfigurationRoundTrips() throws {
    var config = AppConfig.default
    config.refreshIntervalSeconds = 7.5
    config.windowThumbnailsStaleSeconds = 11
    config.dimsStaleThumbnails = true
    config.windowThumbnailTargetSize = CGSize(width: 320, height: 200)
    config.maxWindows = 9
    config.overlayColumns = 6
    config.windowOrder = .stable
    config.overlayGrouping = [.displays, .spaces]
    config.overlayBackground = try OverlayColor(parsing: "#10203040")
    config.hotkey = try HotkeyBinding(parsing: "cmd+shift+t")
    config.ignoredApplications = ["amneziavpn", "some tray app"]
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
    #expect(toml.contains("window_thumbnail_target_width = 240\n"))
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
