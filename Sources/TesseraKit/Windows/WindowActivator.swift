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

  /// How long an application is given to answer, so that one busy with a Space
  /// animation cannot hold the main thread — and with it the overlay — while a step
  /// waits for it.
  private let messagingTimeout: Float

  init(config: AppConfig = .default) {
    self.messagingTimeout = Float(config.unresponsiveAfterSeconds)
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
  func activate(_ window: WindowTile) throws -> Result {
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

  /// Brings a window forward without making its application frontmost.
  ///
  /// Used for stepping through windows while the overlay stays up. Activating the
  /// application would take the keyboard away — and when Accessibility cannot aim
  /// at the window, activating raises whatever it can instead, which is how
  /// stepping onto a Finder window landed on the desktop. Here, failing to aim
  /// means doing nothing at all.
  @discardableResult
  func raiseWithoutActivating(_ window: WindowTile) throws -> Result {
    guard isAccessibilityTrusted else {
      throw WindowActivationError.accessibilityNotTrusted
    }

    let element = try? accessibilityWindow(for: window)
    guard let element else {
      return .couldNotAimAtTheWindow
    }

    unminimizeIfNeeded(element)
    _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    logger.debug("Raised \(window.displayAppName) without activating it")
    return .raisedTheWindow
  }

  /// Quits the owning application, the way ⌘Q would.
  ///
  /// Needs no Accessibility permission, and reaches applications whose windows
  /// Accessibility does not list at all. The application is asked, not killed: it
  /// still gets to prompt about unsaved work.
  func quitApplication(_ window: WindowTile) throws {
    guard let application = NSRunningApplication(processIdentifier: window.processID) else {
      throw WindowActivationError.applicationGone(window.displayAppName)
    }

    // Some applications are the desktop rather than something on it. Quitting
    // Finder takes the wallpaper, the icons and every desktop window with it, and
    // nothing brings it back on its own — measured here, by a switcher that quit it
    // and then could not switch to an empty desktop for the rest of the day,
    // because handing the keyboard to the desktop had nobody left to hand it to.
    // macOS hides Finder's own Quit item for the same reason. The window is closed
    // instead, which is what "close" meant anyway.
    guard !Self.isTheDesktopItself(application) else {
      logger.info("\(window.displayAppName) runs the desktop; closing its window instead")

      return try close(window)
    }

    guard application.terminate() else {
      throw WindowActivationError.actionUnavailable(window.displayAppName, "quit")
    }

    logger.debug("Asked \(window.displayAppName) to quit")
  }

  /// Whether this application is part of the desktop rather than a thing on it.
  private static func isTheDesktopItself(_ application: NSRunningApplication) -> Bool {
    guard let identifier = application.bundleIdentifier else {
      return false
    }

    return ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver"]
      .contains(identifier)
  }

  /// Closes the window by pressing its own close button, the way a person would.
  func close(_ window: WindowTile) throws {
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

  /// Sends a window to another display, and says whether it arrived.
  ///
  /// Which Space a window is on is not something any public interface will change,
  /// but which display it is on is only where its rectangle sits — so this is a
  /// move, not a request to the window server. With displays keeping separate
  /// Spaces, the window lands on whatever Space the other display is showing, which
  /// is as close to moving between Spaces as macOS allows from outside.
  ///
  /// Arrival is judged by where the window ended up rather than by the call
  /// returning: an application may clamp the frame or refuse it outright.
  func send(_ window: WindowTile, toDisplay displayID: CGDirectDisplayID) -> Bool {
    let target = CGDisplayBounds(displayID)

    guard !target.isEmpty else {
      logger.error("Display \(displayID) has no bounds to move a window into")
      return false
    }

    do {
      let frame = try frame(of: window)
      let wanted = DisplayInfo.frame(
        frame, movedFrom: CGDisplayBounds(window.displayID), to: target)
      let landed = try setFrame(wanted, of: window)
      let arrived = target.contains(CGPoint(x: landed.midX, y: landed.midY))

      logger.info(
        "Sent \(window.displayAppName) to display \(displayID): arrived=\(arrived) "
          + "wanted=\(wanted.debugDescription) landed=\(landed.debugDescription)")

      return arrived
    } catch {
      logger.error("Could not move \(window.displayAppName): \(error)")

      return false
    }
  }

  /// Puts a window in a part of the screen it is already on.
  ///
  /// Half a screen and the whole of it, done by geometry rather than by asking the
  /// application: every application's own green button means something slightly
  /// different, and a switcher that tiles windows has to give the same answer
  /// twice running.
  func place(_ window: WindowTile, _ placement: WindowPlacement) -> Bool {
    guard let bounds = DisplayInfo.visibleBounds(of: window.displayID) else {
      logger.error("No room known for display \(window.displayID)")

      return false
    }

    do {
      let landed = try setFrame(placement.frame(in: bounds), of: window)

      logger.info("Placed \(window.displayAppName): landed=\(landed.debugDescription)")

      return true
    } catch {
      logger.error("Could not place \(window.displayAppName): \(error)")

      return false
    }
  }

  /// Turns a window's own fullscreen mode on or off.
  ///
  /// Fullscreen is a mode, not a rectangle: the window is given a Space of its own
  /// and the menu bar goes away, and only the application can do that. Most answer
  /// for `AXFullScreen`; the ones that do not still have a zoom button, which is
  /// what a person would press instead.
  func toggleFullscreen(_ window: WindowTile) -> Bool {
    do {
      let element = try accessibilityWindow(for: window)
      var value: CFTypeRef?
      let attribute = "AXFullScreen" as CFString

      guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
        let isFullscreen = value as? Bool
      else {
        logger.debug("\(window.displayAppName) does not answer for AXFullScreen; zooming instead")

        return press(kAXZoomButtonAttribute, of: element)
      }

      let wanted: CFBoolean = isFullscreen ? kCFBooleanFalse : kCFBooleanTrue
      let status = AXUIElementSetAttributeValue(element, attribute, wanted)

      logger.info(
        "Asked \(window.displayAppName) for fullscreen=\(!isFullscreen): \(status.rawValue)")

      return status == .success
    } catch {
      logger.error("Could not put \(window.displayAppName) fullscreen: \(error)")

      return false
    }
  }

  /// Presses one of a window's own title bar buttons, the way a person would.
  private func press(_ button: String, of element: AXUIElement) -> Bool {
    var buttonValue: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(element, button as CFString, &buttonValue) == .success,
      let buttonValue, CFGetTypeID(buttonValue) == AXUIElementGetTypeID()
    else {
      return false
    }

    let status = AXUIElementPerformAction(
      unsafeDowncast(buttonValue, to: AXUIElement.self), kAXPressAction as CFString)

    return status == .success
  }

  /// Where a window is, as Accessibility sees it — the live rectangle rather than
  /// the one the last capture recorded.
  func frame(of window: WindowTile) throws -> CGRect {
    let element = try accessibilityWindow(for: window)

    guard let frame = Self.frame(of: element) else {
      throw WindowActivationError.actionUnavailable(window.displayAppName, "read its position")
    }

    return frame
  }

  /// Puts a window where it is asked to go, and says where it actually ended up.
  ///
  /// A window belongs to the display covering most of it, so sending one to another
  /// display is moving its rectangle there — there is no display to set. Both
  /// attributes are requests, not commands: an application may clamp the size, keep
  /// a minimum, or refuse outright, so the frame is read back rather than assumed.
  /// The position is set twice because a resize can push a window back onto the
  /// display it came from.
  @discardableResult
  func setFrame(_ frame: CGRect, of window: WindowTile) throws -> CGRect {
    let element = try accessibilityWindow(for: window)

    Self.set(frame.origin, on: element)
    Self.set(frame.size, on: element)
    Self.set(frame.origin, on: element)

    guard let landed = Self.frame(of: element) else {
      throw WindowActivationError.actionUnavailable(window.displayAppName, "move")
    }

    logger.debug("Asked \(window.displayAppName) to move to \(frame.debugDescription)")

    return landed
  }

  private static func set(_ origin: CGPoint, on element: AXUIElement) {
    var origin = origin

    guard let wrapped = AXValueCreate(.cgPoint, &origin) else {
      return
    }

    _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, wrapped)
  }

  private static func set(_ size: CGSize, on element: AXUIElement) {
    var size = size

    guard let wrapped = AXValueCreate(.cgSize, &size) else {
      return
    }

    _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, wrapped)
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        == .success,
      AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
      let positionValue, let sizeValue,
      CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else {
      return nil
    }

    var origin = CGPoint.zero
    var size = CGSize.zero

    guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin),
      AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
    else {
      return nil
    }

    return CGRect(origin: origin, size: size)
  }

  /// The Accessibility element for a tile, matched by title.
  ///
  /// Not every window is there to be found: Accessibility lists none of Finder's
  /// browser windows, for one. Saying so is better than acting on whichever window
  /// it does offer.
  private func accessibilityWindow(for window: WindowTile) throws -> AXUIElement {
    guard isAccessibilityTrusted else {
      throw WindowActivationError.accessibilityNotTrusted
    }

    let application = AXUIElementCreateApplication(window.processID)
    AXUIElementSetMessagingTimeout(application, messagingTimeout)

    var windowsValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      application, kAXWindowsAttribute as CFString, &windowsValue)
    let windows = (windowsValue as? [AXUIElement]) ?? []

    guard status == .success, let match = matchingWindow(among: windows, title: window.title) else {
      // What Accessibility did offer, when it did not offer the window asked for.
      // Usually the answer is that the window is on a Space that is not showing.
      logger.debug(
        "Accessibility listed \(windows.count) window(s) of \(window.displayAppName): "
          + windows.compactMap(accessibilityTitle(of:)).joined(separator: " | "))

      throw WindowActivationError.windowNotListed(window.displayAppName, window.displayTitle)
    }

    return match
  }

  private func raiseWindow(processID: pid_t, title: String) -> Result {
    let applicationElement = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(applicationElement, messagingTimeout)

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

    let matched = matchingWindow(among: windows, title: title)
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

  /// The window Accessibility lists under `title`, when it can be told apart.
  private func matchingWindow(among windows: [AXUIElement], title: String) -> AXUIElement? {
    let titles = windows.map { accessibilityTitle(of: $0) ?? "" }

    guard let index = WindowTitleMatch.index(of: title, among: titles) else {
      return nil
    }

    return windows[index]
  }

  private func accessibilityTitle(of element: AXUIElement) -> String? {
    var titleValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)

    guard status == .success else {
      return nil
    }

    return titleValue as? String
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
