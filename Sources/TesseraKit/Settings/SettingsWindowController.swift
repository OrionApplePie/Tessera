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
  private var hasBeenPresented = false

  init(config: AppConfig, configURL: URL, debugMode: Bool) {
    self.configURL = configURL
    self.logger = AppLogger(debugMode: debugMode, category: .config)
    self.model = SettingsModel(config: config)

    // A settings window is not resized: nothing in it benefits from more room, and
    // a form that can be dragged out of shape is a form that will be.
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.contentSize(for: model)),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = localized("Tessera Settings")
    window.isReleasedWhenClosed = false

    // Reopens where it was left, which is what every other settings window on the
    // system does. Only the first one is centred.
    window.setFrameAutosaveName("TesseraSettings")

    // No fullscreen either: a settings window that takes over a display is a
    // settings window someone has to find their way back out of.
    window.collectionBehavior = [.fullScreenNone]

    super.init(window: window)

    let hostingView = NSHostingView(
      rootView: SettingsView(
        model: model,
        onSave: { [weak self] in self?.save() },
        onCancel: { [weak self] in self?.close() }
      ))

    // The window's size is decided here, from the measurement above, and the view
    // is not allowed to renegotiate it page by page — a window that changes height
    // when you click a section reads as a glitch rather than as a fit.
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView
  }

  /// How wide a settings window is here: enough for a sidebar and a form of
  /// labelled controls, and no wider. Left to its own fitting size the form spreads
  /// to whatever its longest label allows, which reads as a document window rather
  /// than as settings.
  private static let contentWidth: CGFloat = 560

  /// The height of the page that needs the most room, at that width.
  ///
  /// Measured rather than chosen, so that adding a setting to any page cannot
  /// quietly clip it, and so that no page is asked to sit in a window sized for a
  /// different one.
  private static func contentSize(for model: SettingsModel) -> NSSize {
    // Measured inside a window rather than on a loose view: a view that is not in a
    // window reports a different height for the same content, as the overlay's own
    // fitting pass found. The pages are measured with their vertical size fixed, so
    // that the form reports what it draws rather than what it could be squeezed to.
    let probe = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 100),
      styleMask: [.titled],
      backing: .buffered,
      defer: true
    )

    let height = SettingsSection.allCases.reduce(into: CGFloat(0)) { tallest, section in
      let page = NSHostingView(
        rootView: SettingsView(
          model: model, section: section, measuring: true, onSave: {}, onCancel: {}))
      probe.contentView = page
      probe.layoutIfNeeded()

      tallest = max(tallest, page.fittingSize.height, probe.contentMinSize.height)
    }

    // And no taller than the smallest screen attached, not the one it happens to
    // open on: a window sized for a 1440-point display cannot be dragged back into
    // view on a laptop. A page can outgrow that — the list of keys does — and a
    // grouped form scrolls on its own, so the room it does not get is room it can
    // still reach.
    let smallest = NSScreen.screens.map(\.visibleFrame.height).min() ?? 900
    let room = smallest * 0.8

    return NSSize(width: contentWidth, height: min(height, room))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    if !hasBeenPresented {
      window?.center()
      hasBeenPresented = true
    }

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
