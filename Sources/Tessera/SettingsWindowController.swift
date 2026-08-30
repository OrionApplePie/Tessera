import AppKit
import Foundation
import SwiftUI

/// Hosts the settings window and does what saving means: write the file, then
/// replace the running background app with one that has read it.
@MainActor
final class SettingsWindowController: NSWindowController {
  private let configURL: URL
  private let logger: AppLogger
  private let model: SettingsModel

  init(config: AppConfig, configURL: URL, debugMode: Bool) {
    self.configURL = configURL
    self.logger = AppLogger(debugMode: debugMode, category: .config)
    self.model = SettingsModel(config: config)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Tessera Settings"
    window.isReleasedWhenClosed = false

    super.init(window: window)

    window.contentView = NSHostingView(
      rootView: SettingsView(
        model: model,
        onSave: { [weak self] in self?.save() },
        onCancel: { [weak self] in self?.close() }
      ))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    window?.center()
    showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func save() {
    guard let config = model.makeConfig() else {
      logger.info("Settings not saved; the form has a problem")
      return
    }

    do {
      try AppConfigWriter.write(config, to: configURL)
      logger.info("Wrote settings to \(configURL.path)")
    } catch {
      logger.error("Failed to write \(configURL.path): \(error)")
      return
    }

    close()

    do {
      // The configuration is read once at launch, so the way to apply it is to be
      // launched again. The replacement is asked for by a separate process, which
      // waits for this one to let go of the single-instance lock first.
      try BackgroundAppLauncher.requestRestart()
    } catch {
      logger.error("Saved, but could not restart: \(error)")
    }
  }
}
