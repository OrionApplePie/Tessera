import AppKit
import ApplicationServices

/// Raises a window through the application's own Window menu.
///
/// Accessibility lists only the windows on the active Space, and every fullscreen
/// window is a Space of its own — so two fullscreen windows of one application
/// cannot be reached from each other. Measured on VS Code: with one of them
/// showing, `kAXWindowsAttribute` names that one and nothing else, and Apple Events
/// reach neither, because Electron applications are not scriptable.
///
/// The Window menu is the exception. It lists every window of the application by
/// title, across Spaces — measured against exactly that pair — and pressing an item
/// raises the window it names. It needs the Accessibility permission the switcher
/// already asks for, and nothing else.
@MainActor
struct WindowMenuActivator {
  private let timeout: TimeInterval
  private let logger: AppLogger

  init(timeout: TimeInterval, debugMode: Bool) {
    self.timeout = timeout
    self.logger = AppLogger(debugMode: debugMode, category: .preview)
  }

  /// Presses the menu item that names this window, and says whether it found one.
  func raiseWindow(titled title: String, processID: pid_t) -> Bool {
    guard !title.isEmpty else {
      return false
    }

    guard let item = menuItem(naming: title, ofApplicationWithProcessID: processID) else {
      logger.debug("No menu item names \"\(title)\" in pid \(processID)")
      return false
    }

    let status = AXUIElementPerformAction(item, kAXPressAction as CFString)
    guard status == .success else {
      logger.warning("Pressing the menu item for \"\(title)\" failed: \(status.rawValue)")
      return false
    }

    logger.info("Raised the window through its application's Window menu")
    return true
  }

  /// The item naming this window, searched menu by menu from the end.
  ///
  /// Every question here is a round trip to another application, and an application
  /// in the middle of a Space switch answers slowly — without a limit, one of those
  /// round trips froze the overlay for as long as it took. So the messaging timeout
  /// is set, and the search stops at the first menu that names the window: Window
  /// and Help are the last two menus, and walking File and Edit first costs a round
  /// trip per item for nothing. Measured across Word, Code and Telegram: the whole
  /// menu bar is 7-24ms when the application is idle, the search from the end 1-9ms.
  private func menuItem(
    naming title: String,
    ofApplicationWithProcessID processID: pid_t
  ) -> AXUIElement? {
    let application = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(application, Float(timeout))

    var menuBarValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &menuBarValue)
        == .success,
      let menuBarValue,
      CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
    else {
      return nil
    }

    let menuBar = unsafeDowncast(menuBarValue, to: AXUIElement.self)

    for menu in children(of: menuBar).reversed() {
      // Only items directly under a menu are considered, which is what keeps this
      // from pressing something in "Open Recent": its entries are one level deeper
      // and would open a second window rather than raise the one asked for.
      let items = children(of: menu)
        .flatMap { children(of: $0) }
        .filter { isEnabled($0) }
      let titles = items.map { self.title(of: $0) ?? "" }

      if let index = WindowTitleMatch.index(of: title, among: titles) {
        return items[index]
      }
    }

    return nil
  }

  private func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
      let raw = value as? [AnyObject]
    else {
      return []
    }

    return raw.compactMap { child in
      guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
        return nil
      }

      return unsafeDowncast(child, to: AXUIElement.self)
    }
  }

  private func title(of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success
    else {
      return nil
    }

    return value as? String
  }

  /// A menu item for a window that cannot be chosen is not the window's item: a
  /// disabled entry is a heading or a command that does not apply right now.
  private func isEnabled(_ element: AXUIElement) -> Bool {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success
    else {
      return true
    }

    return value as? Bool ?? true
  }
}
