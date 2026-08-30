import AppKit
import ApplicationServices
import Foundation

/// Brings a window to the front.
///
/// Two steps are needed and neither is sufficient alone: activating the owning
/// application makes it frontmost, and raising the specific `AXUIElement` picks
/// the right window out of that application's several.
@MainActor
struct WindowActivator {
  private let logger: AppLogger

  init(config: AppConfig = .default) {
    self.logger = AppLogger(debugMode: config.debugMode, category: .app)
  }

  /// Whether the Accessibility permission needed to raise a specific window is granted.
  var isAccessibilityTrusted: Bool {
    AXIsProcessTrusted()
  }

  /// Asks macOS to show the Accessibility permission prompt for this process.
  @discardableResult
  func requestAccessibilityPermission() -> Bool {
    // The imported `kAXTrustedCheckOptionPrompt` global is a `var`, which Swift 6
    // rejects as shared mutable state. Its documented value is stable, so use it directly.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// What actually happened, which decides whether the outcome means anything.
  ///
  /// Accessibility does not expose every window of every application — Finder's
  /// browser windows, for one, are absent while the desktop is not — and raising
  /// then falls back to whatever window it does offer. An activation that could not
  /// aim at the window it was given proves nothing about that window.
  enum Result {
    case raisedTheWindow
    case couldNotAimAtTheWindow
  }

  @discardableResult
  func activate(_ window: WindowTileModel) throws -> Result {
    guard let application = NSRunningApplication(processIdentifier: window.processID) else {
      throw WindowActivationError.applicationGone(window.displayAppName)
    }

    application.activate(options: [])
    logger.debug("Activated application \(window.displayAppName)")

    guard isAccessibilityTrusted else {
      // The app is frontmost, which is most of the way there. Raising the exact
      // window needs Accessibility, so say so rather than failing silently.
      throw WindowActivationError.accessibilityNotTrusted
    }

    return raiseWindow(processID: window.processID, title: window.title)
  }

  private func raiseWindow(processID: pid_t, title: String) -> Result {
    let applicationElement = AXUIElementCreateApplication(processID)

    var windowsValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXWindowsAttribute as CFString,
      &windowsValue
    )

    guard status == .success, let windows = windowsValue as? [AXUIElement] else {
      logger.warning("Accessibility returned no window list for pid \(processID)")
      return .couldNotAimAtTheWindow
    }

    let matched = windows.first { matchesTitle(element: $0, title: title) }
    let target = matched ?? windows.first

    guard let target else {
      logger.warning("Accessibility window list was empty for pid \(processID)")
      return .couldNotAimAtTheWindow
    }

    if matched == nil {
      logger.warning(
        "Accessibility does not list a window titled \"\(title)\" for pid \(processID); "
          + "raising whatever it does list instead"
      )
    }

    unminimizeIfNeeded(target)
    _ = AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    logger.debug("Raised window via Accessibility")
    return matched == nil ? .couldNotAimAtTheWindow : .raisedTheWindow
  }

  /// Raising a minimized window does nothing: it has to come out of the Dock first.
  private func unminimizeIfNeeded(_ element: AXUIElement) {
    var minimizedValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      element,
      kAXMinimizedAttribute as CFString,
      &minimizedValue
    )

    guard status == .success, let isMinimized = minimizedValue as? Bool, isMinimized else {
      return
    }

    _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    logger.debug("Unminimized window via Accessibility")
  }

  private func matchesTitle(element: AXUIElement, title: String) -> Bool {
    guard !title.isEmpty else {
      return false
    }

    var titleValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)

    guard status == .success, let elementTitle = titleValue as? String else {
      return false
    }

    return elementTitle == title
  }
}

enum WindowActivationError: Error, CustomStringConvertible {
  case applicationGone(String)
  case accessibilityNotTrusted

  var description: String {
    switch self {
    case .applicationGone(let appName):
      return "\(appName) is no longer running"
    case .accessibilityNotTrusted:
      return
        "Accessibility permission is not granted, so only the application was activated. "
        + "Grant it in System Settings > Privacy & Security > Accessibility."
    }
  }
}
