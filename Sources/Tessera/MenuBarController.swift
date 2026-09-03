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

  private let pauseItem = NSMenuItem(
    title: "Pause Background Refresh", action: nil, keyEquivalent: "")
  private let resumeItem = NSMenuItem(
    title: "Resume Background Refresh", action: nil, keyEquivalent: "")
  private let accessibilityItem = NSMenuItem(
    title: "Grant Accessibility Permission…", action: nil, keyEquivalent: "")
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
    pauseItem.isEnabled = !windowCoordinator.isRefreshPaused
    resumeItem.isEnabled = windowCoordinator.isRefreshPaused
    // Nothing to grant once the permission is already there.
    accessibilityItem.isHidden = windowCoordinator.isAccessibilityTrusted

    let unreachable = windowCoordinator.unreachableDesktops
    tooManySpacesItem.isHidden = unreachable == 0
    tooManySpacesItem.title = String(
      localized: "\(unreachable) desktop(s) past the eighth have no macOS shortcut")
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
      NSMenuItem(title: "Show Switcher", action: #selector(showSwitcherAction), keyEquivalent: ""))
    menu.addItem(
      NSMenuItem(title: "Refresh Now", action: #selector(refreshNowAction), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())

    pauseItem.action = #selector(pauseRefreshAction)
    resumeItem.action = #selector(resumeRefreshAction)
    accessibilityItem.action = #selector(requestAccessibilityAction)
    menu.addItem(pauseItem)
    menu.addItem(resumeItem)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(accessibilityItem)
    tooManySpacesItem.isEnabled = false
    menu.addItem(tooManySpacesItem)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ","))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))

    for item in menu.items where item.action != nil {
      item.target = self
    }

    statusItem.menu = menu
    updateRefreshItems()
  }

  @objc private func showSwitcherAction() {
    showSwitcher()
  }

  @objc private func refreshNowAction() {
    refreshNow()
  }

  @objc private func pauseRefreshAction() {
    pauseRefresh()
    updateRefreshItems()
  }

  @objc private func resumeRefreshAction() {
    resumeRefresh()
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
