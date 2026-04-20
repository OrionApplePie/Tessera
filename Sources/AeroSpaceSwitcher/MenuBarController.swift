import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let previewCoordinator: PreviewCoordinator
    private let showSwitcher: () -> Void
    private let refreshNow: () -> Void
    private let pauseRefresh: () -> Void
    private let resumeRefresh: () -> Void
    private let quit: () -> Void

    private let pauseItem = NSMenuItem(title: "Pause Background Refresh", action: nil, keyEquivalent: "")
    private let resumeItem = NSMenuItem(title: "Resume Background Refresh", action: nil, keyEquivalent: "")

    init(
        previewCoordinator: PreviewCoordinator,
        showSwitcher: @escaping () -> Void,
        refreshNow: @escaping () -> Void,
        pauseRefresh: @escaping () -> Void,
        resumeRefresh: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.previewCoordinator = previewCoordinator
        self.showSwitcher = showSwitcher
        self.refreshNow = refreshNow
        self.pauseRefresh = pauseRefresh
        self.resumeRefresh = resumeRefresh
        self.quit = quit
        super.init()

        configureStatusItem()
    }

    func updateRefreshItems() {
        pauseItem.isEnabled = !previewCoordinator.isRefreshPaused
        resumeItem.isEnabled = previewCoordinator.isRefreshPaused
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.3.group",
                accessibilityDescription: "AeroSpace Switcher"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Switcher", action: #selector(showSwitcherAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNowAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        pauseItem.action = #selector(pauseRefreshAction)
        resumeItem.action = #selector(resumeRefreshAction)
        menu.addItem(pauseItem)
        menu.addItem(resumeItem)
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

    @objc private func quitAction() {
        quit()
    }
}

