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

  /// Quits the owning application, the way ⌘Q would.
  ///
  /// Needs no Accessibility permission, and reaches applications whose windows
  /// Accessibility does not list at all. The application is asked, not killed: it
  /// still gets to prompt about unsaved work.
  func quitApplication(_ window: WindowTileModel) throws {
    guard let application = NSRunningApplication(processIdentifier: window.processID) else {
      throw WindowActivationError.applicationGone(window.displayAppName)
    }

    guard application.terminate() else {
      throw WindowActivationError.actionUnavailable(window.displayAppName, "quit")
    }

    logger.debug("Asked \(window.displayAppName) to quit")
  }

  /// Closes the window by pressing its own close button, the way a person would.
  func close(_ window: WindowTileModel) throws {
    let element = try accessibilityWindow(for: window)

    var buttonValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &buttonValue)
        == .success,
      let buttonValue,
      CFGetTypeID(buttonValue) == AXUIElementGetTypeID()
    else {
      throw WindowActivationError.actionUnavailable(window.displayAppName, "close")
    }

    // Accessibility returns an untyped CFTypeRef. Swift rejects a conditional cast
    // here — it would always succeed — and this project forbids a force cast, so
    // the type is checked by its CFTypeID and then reinterpreted.
    let button = unsafeDowncast(buttonValue, to: AXUIElement.self)
    _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
    logger.debug("Pressed the close button of a window")
  }

  /// The Accessibility element for a tile, matched by title.
  ///
  /// Not every window is there to be found: Accessibility lists none of Finder's
  /// browser windows, for one. Saying so is better than acting on whichever window
  /// it does offer.
  private func accessibilityWindow(for window: WindowTileModel) throws -> AXUIElement {
    guard isAccessibilityTrusted else {
      throw WindowActivationError.accessibilityNotTrusted
    }

    let application = AXUIElementCreateApplication(window.processID)

    var windowsValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue)
        == .success,
      let windows = windowsValue as? [AXUIElement],
      let match = windows.first(where: { matchesTitle(element: $0, title: window.title) })
    else {
      throw WindowActivationError.windowNotListed(window.displayAppName, window.displayTitle)
    }

    return match
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
  case windowNotListed(String, String)
  case actionUnavailable(String, String)

  var description: String {
    switch self {
    case .applicationGone(let appName):
      return "\(appName) is no longer running"
    case .windowNotListed(let appName, let title):
      return
        "Accessibility does not list \(appName)'s window \"\(title)\", so nothing can be done "
        + "to it from here. Finder's windows are missing from it entirely."
    case .actionUnavailable(let appName, let action):
      return "\(appName)'s window does not offer \(action)"
    case .accessibilityNotTrusted:
      return
        "Accessibility permission is not granted, so only the application was activated. "
        + "Grant it in System Settings > Privacy & Security > Accessibility."
    }
  }
}
