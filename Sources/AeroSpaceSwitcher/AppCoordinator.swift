import AppKit

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let config: AppConfig
    private let client = AeroSpaceClient()
    private lazy var previewCoordinator = PreviewCoordinator(client: client, config: config)
    private var overlayWindowController: OverlayWindowController?
    private var menuBarController: MenuBarController?

    init(config: AppConfig) {
        self.config = config
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        previewCoordinator.start()
        overlayWindowController = OverlayWindowController(
            previewCoordinator: previewCoordinator,
            closeAfterWorkspaceSwitch: config.closeAfterWorkspaceSwitch
        )

        if config.showMenuBarIcon {
            menuBarController = MenuBarController(
                previewCoordinator: previewCoordinator,
                showSwitcher: { [weak self] in self?.showOverlay() },
                refreshNow: { [weak self] in self?.refreshNow() },
                pauseRefresh: { [weak self] in self?.pauseRefresh() },
                resumeRefresh: { [weak self] in self?.resumeRefresh() },
                quit: { [weak self] in self?.quit() }
            )
        }

        registerExternalShowNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func start() {
        previewCoordinator.start()
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        overlayWindowController?.hideOverlay()
        previewCoordinator.stop()
    }

    func pauseRefresh() {
        previewCoordinator.pauseRefresh()
        menuBarController?.updateRefreshItems()
    }

    func resumeRefresh() {
        previewCoordinator.resumeRefresh()
        menuBarController?.updateRefreshItems()
    }

    func refreshNow() {
        Task { @MainActor [weak self] in
            await self?.previewCoordinator.refreshNow()
        }
    }

    func showOverlay() {
        overlayWindowController?.showOverlay()
    }

    func hideOverlay() {
        overlayWindowController?.hideOverlay()
    }

    func toggleOverlay() {
        guard overlayWindowController?.isOverlayVisible == true else {
            showOverlay()
            return
        }

        hideOverlay()
    }

    func quit() {
        stop()
        NSApp.terminate(nil)
    }

    private func registerExternalShowNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showOverlayNotification(_:)),
            name: BackgroundAppNotifications.showSwitcher,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggleOverlayNotification(_:)),
            name: BackgroundAppNotifications.toggleSwitcher,
            object: nil
        )
    }

    @objc private func showOverlayNotification(_ notification: Notification) {
        showOverlay()
    }

    @objc private func toggleOverlayNotification(_ notification: Notification) {
        toggleOverlay()
    }
}
