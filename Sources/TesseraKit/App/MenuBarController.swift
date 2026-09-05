import AppKit

@MainActor
final class MenuBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let windowCoordinator: WindowCoordinator
  private let showSwitcher: () -> Void
  private let refreshNow: () -> Void
  private let pauseRefresh: () -> Void
  private let resumeRefresh: () -> Void
  private let requestAccessibility: () -> Void
  private let openSettings: () -> Void
  private let quit: () -> Void

  /// One item rather than two. Refreshing is either on or off, and a menu that
  /// offers both at once makes the reader work out which of them is the state and
  /// which is the offer.
  private let refreshToggleItem = NSMenuItem(
    title: localized("Pause Background Refresh"), action: nil, keyEquivalent: "")
  private let accessibilityItem = NSMenuItem(
    title: localized("Grant Accessibility Permission…"), action: nil, keyEquivalent: "")
  /// Shown only when there are more desktops than macOS binds shortcuts to, because
  /// those last ones cannot be switched to when they are empty.
  private let tooManySpacesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  init(
    windowCoordinator: WindowCoordinator,
    showSwitcher: @escaping () -> Void,
    refreshNow: @escaping () -> Void,
    pauseRefresh: @escaping () -> Void,
    resumeRefresh: @escaping () -> Void,
    requestAccessibility: @escaping () -> Void,
    openSettings: @escaping () -> Void,
    quit: @escaping () -> Void
  ) {
    self.windowCoordinator = windowCoordinator
    self.showSwitcher = showSwitcher
    self.refreshNow = refreshNow
    self.pauseRefresh = pauseRefresh
    self.resumeRefresh = resumeRefresh
    self.requestAccessibility = requestAccessibility
    self.openSettings = openSettings
    self.quit = quit
    super.init()

    configureStatusItem()
  }

  func updateRefreshItems() {
    let paused = windowCoordinator.isRefreshPaused

    refreshToggleItem.title =
      paused
      ? localized("Resume Background Refresh")
      : localized("Pause Background Refresh")
    refreshToggleItem.image = Self.icon(paused ? "play" : "pause")
    // Nothing to grant once the permission is already there.
    accessibilityItem.isHidden = windowCoordinator.isAccessibilityTrusted

    let unreachable = windowCoordinator.unreachableDesktops
    tooManySpacesItem.isHidden = unreachable == 0
    tooManySpacesItem.title = localized(
      "%lld desktop(s) past the eighth have no macOS shortcut", unreachable)
  }

  private func configureStatusItem() {
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "square.grid.2x2",
        accessibilityDescription: "Tessera"
      )
      button.image?.isTemplate = true
    }

    let menu = NSMenu()
    menu.addItem(
      item(
        localized("Show Switcher"), symbol: "square.grid.2x2", action: #selector(showSwitcherAction)
      ))
    menu.addItem(NSMenuItem.separator())

    // The two ways of saying "look again" stand together: one does it now, the
    // other decides whether it keeps happening on its own.
    menu.addItem(
      item(localized("Refresh Now"), symbol: "arrow.clockwise", action: #selector(refreshNowAction))
    )
    refreshToggleItem.action = #selector(toggleRefreshAction)
    menu.addItem(refreshToggleItem)
    menu.addItem(NSMenuItem.separator())

    accessibilityItem.action = #selector(requestAccessibilityAction)
    accessibilityItem.image = Self.icon("hand.raised")
    menu.addItem(accessibilityItem)
    tooManySpacesItem.isEnabled = false
    tooManySpacesItem.image = Self.icon("exclamationmark.triangle")
    menu.addItem(tooManySpacesItem)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        localized("Settings…"), symbol: "gearshape", action: #selector(openSettingsAction), key: ","
      ))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(localized("Quit"), symbol: "power", action: #selector(quitAction), key: "q"))

    for item in menu.items where item.action != nil {
      item.target = self
    }

    statusItem.menu = menu
    updateRefreshItems()
  }

  /// A menu item with the picture that goes with it. The pictures are the system's
  /// own symbols, drawn as templates so they follow the menu's own colour in either
  /// appearance.
  private func item(
    _ title: String,
    symbol: String,
    action: Selector,
    key: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.image = Self.icon(symbol)

    return item
  }

  private static func icon(_ symbol: String) -> NSImage? {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    image?.isTemplate = true

    return image
  }

  @objc private func showSwitcherAction() {
    showSwitcher()
  }

  @objc private func refreshNowAction() {
    refreshNow()
  }

  @objc private func toggleRefreshAction() {
    if windowCoordinator.isRefreshPaused {
      resumeRefresh()
    } else {
      pauseRefresh()
    }

    updateRefreshItems()
  }

  @objc private func requestAccessibilityAction() {
    requestAccessibility()
    updateRefreshItems()
  }

  @objc private func openSettingsAction() {
    openSettings()
  }

  @objc private func quitAction() {
    quit()
  }
}
