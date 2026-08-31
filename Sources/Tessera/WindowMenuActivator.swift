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
  private let logger: AppLogger

  init(debugMode: Bool) {
    self.logger = AppLogger(debugMode: debugMode, category: .preview)
  }

  /// Presses the menu item that names this window, and says whether it found one.
  ///
  /// Only items directly under a menu are considered. That is what keeps this from
  /// pressing something in "Open Recent", whose entries are one level deeper and
  /// would open a second window rather than raise the one asked for.
  func raiseWindow(titled title: String, processID: pid_t) -> Bool {
    guard !title.isEmpty else {
      return false
    }

    let items = menuItems(ofApplicationWithProcessID: processID)
    guard let index = WindowTitleMatch.index(of: title, among: items.map(\.title)) else {
      logger.debug("No menu item names \"\(title)\" in pid \(processID)")
      return false
    }

    let status = AXUIElementPerformAction(items[index].element, kAXPressAction as CFString)
    guard status == .success else {
      logger.warning("Pressing the menu item for \"\(title)\" failed: \(status.rawValue)")
      return false
    }

    logger.info("Raised the window through its application's Window menu")
    return true
  }

  private func menuItems(ofApplicationWithProcessID processID: pid_t) -> [(
    element: AXUIElement, title: String
  )] {
    let application = AXUIElementCreateApplication(processID)

    var menuBarValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &menuBarValue)
        == .success,
      let menuBarValue,
      CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
    else {
      return []
    }

    let menuBar = unsafeDowncast(menuBarValue, to: AXUIElement.self)

    return children(of: menuBar)
      .flatMap { children(of: $0) }
      .flatMap { children(of: $0) }
      .compactMap { item in
        guard let title = title(of: item), !title.isEmpty, isEnabled(item) else {
          return nil
        }

        return (item, title)
      }
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
