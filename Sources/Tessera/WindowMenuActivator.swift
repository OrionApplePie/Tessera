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

    guard let found = menuItem(naming: title, ofApplicationWithProcessID: processID) else {
      logger.debug("No menu item names \"\(title)\" in pid \(processID)")
      return false
    }

    let status = AXUIElementPerformAction(found.item, kAXPressAction as CFString)
    close(found.menu)

    guard status == .success else {
      logger.warning("Pressing the menu item for \"\(title)\" failed: \(status.rawValue)")
      return false
    }

    logger.info("Raised the window through its application's Window menu")
    return true
  }

  /// Reading a menu's items is not free of consequence: an application whose menu
  /// bar is on screen may put the menu up while it is read. Measured on Word, whose
  /// menus stood open for 1.3 seconds after a pass over the whole bar — which is
  /// what "the menu opens by itself" was. Closing each menu that was opened brings
  /// that back to a frame or two, and reading only one menu usually avoids it.
  private func close(_ menu: AXUIElement) {
    _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
  }

  /// The item naming this window, and the menu it was found in.
  ///
  /// Only the Window menu is read. Walking the whole bar is what made applications
  /// show their menus — and it is unnecessary: a top level menu's title can be read
  /// without opening it, which is how the Window menu is found. Failing that, the
  /// last two are tried, because Window sits before Help at the end of the bar in
  /// every application that has one.
  private func menuItem(
    naming title: String,
    ofApplicationWithProcessID processID: pid_t
  ) -> (item: AXUIElement, menu: AXUIElement)? {
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

    for menu in windowMenus(among: children(of: menuBar)) {
      // Only items directly under a menu are considered, which is what keeps this
      // from pressing something in "Open Recent": its entries are one level deeper
      // and would open a second window rather than raise the one asked for.
      let items = children(of: menu)
        .flatMap { children(of: $0) }
        .filter { isEnabled($0) }
      let titles = items.map { self.title(of: $0) ?? "" }

      if let index = WindowTitleMatch.index(of: title, among: titles) {
        return (items[index], menu)
      }

      close(menu)
    }

    return nil
  }

  /// The menus worth opening: the one called Window in the application's own
  /// language, and failing that the two at the end of the bar.
  private func windowMenus(among menus: [AXUIElement]) -> [AXUIElement] {
    let named = menus.filter { Self.windowMenuNames.contains(title(of: $0) ?? "") }

    return named.isEmpty ? Array(menus.suffix(2).reversed()) : named
  }

  /// What applications here call the menu that lists their windows. Not a complete
  /// list of languages, and it does not need to be: an application whose menu is
  /// named something else falls back to position, which is the same menu.
  private static let windowMenuNames: Set<String> = [
    "Window", "Окно", "Fenster", "Fenêtre", "Ventana", "Finestra", "Janela",
    "Venster", "Okno", "Pencere", "Vindu", "Fönster", "Ikkuna", "ウインドウ", "窗口", "視窗", "창",
  ]

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
