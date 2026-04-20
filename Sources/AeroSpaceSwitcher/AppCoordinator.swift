import AppKit

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let config: AppConfig
    private let logger: AppLogger
    private let hotkeyLogger: AppLogger
    private let client = AeroSpaceClient()
    private lazy var previewCoordinator = PreviewCoordinator(client: client, config: config)
    private var overlayWindowController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var isStopped = false

    init(config: AppConfig) {
        self.config = config
        self.logger = AppLogger(debugMode: config.debugMode, category: .app)
        self.hotkeyLogger = AppLogger(debugMode: config.debugMode, category: .hotkey)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logger.info("Application did finish launching")

        previewCoordinator.start()
        overlayWindowController = OverlayWindowController(
            previewCoordinator: previewCoordinator,
            closeAfterWorkspaceSwitch: config.closeAfterWorkspaceSwitch,
            debugMode: config.debugMode
        )

        if config.showMenuBarIcon {
            menuBarController = MenuBarController(
                previewCoordinator: previewCoordinator,
                showSwitcher: { [weak self] in self?.showOverlay(source: .menuBarAction) },
                refreshNow: { [weak self] in self?.refreshNow() },
                pauseRefresh: { [weak self] in self?.pauseRefresh() },
                resumeRefresh: { [weak self] in self?.resumeRefresh() },
                quit: { [weak self] in self?.quit() }
            )
        } else {
            logger.info("Menu bar icon disabled by config")
        }

        registerExternalShowNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application will terminate")
        stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func start() {
        logger.debug("Starting app coordinator")
        previewCoordinator.start()
    }

    func stop() {
        guard !isStopped else {
            return
        }

        isStopped = true
        logger.info("Stopping app coordinator")
        DistributedNotificationCenter.default().removeObserver(self)
        overlayWindowController?.hideOverlay()
        previewCoordinator.stop()
    }

    func pauseRefresh() {
        logger.info("Pausing background refresh")
        previewCoordinator.pauseRefresh()
        menuBarController?.updateRefreshItems()
    }

    func resumeRefresh() {
        logger.info("Resuming background refresh")
        previewCoordinator.resumeRefresh()
        menuBarController?.updateRefreshItems()
    }

    func refreshNow() {
        logger.info("Manual preview refresh requested")
        Task { @MainActor [weak self] in
            await self?.previewCoordinator.refreshNow()
        }
    }

    func showOverlay(source: AppCommandSource = .internalActivation) {
        logger.info("Showing overlay source=\(source.rawValue)")
        overlayWindowController?.showOverlay()
    }

    func hideOverlay() {
        logger.info("Hiding overlay")
        overlayWindowController?.hideOverlay()
    }

    func toggleOverlay(source: AppCommandSource = .internalActivation) {
        guard overlayWindowController?.isOverlayVisible == true else {
            showOverlay(source: source)
            return
        }

        hideOverlay()
    }

    func quit() {
        logger.info("Quit requested")
        stop()
        NSApp.terminate(nil)
    }

    private func registerExternalShowNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showOverlayNotification(_:)),
            name: BackgroundAppNotifications.showSwitcher,
            object: BackgroundAppNotifications.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggleOverlayNotification(_:)),
            name: BackgroundAppNotifications.toggleSwitcher,
            object: BackgroundAppNotifications.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(quitAppNotification(_:)),
            name: BackgroundAppNotifications.quitApp,
            object: BackgroundAppNotifications.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func showOverlayNotification(_ notification: Notification) {
        let metadata = externalTriggerMetadata(
            from: notification,
            expectedSources: [.externalShowCommand]
        )
        logExternalTriggerMetadata(metadata, action: "show")

        showOverlay(source: metadata.source)
    }

    @objc private func toggleOverlayNotification(_ notification: Notification) {
        let metadata = externalTriggerMetadata(
            from: notification,
            expectedSources: [.externalToggleCommand]
        )
        logExternalTriggerMetadata(metadata, action: "toggle")

        toggleOverlay(source: metadata.source)
    }

    @objc private func quitAppNotification(_ notification: Notification) {
        let metadata = externalTriggerMetadata(
            from: notification,
            expectedSources: [.externalQuitCommand, .externalRestartCommand]
        )
        logExternalTriggerMetadata(metadata, action: "quit")

        quit()
    }

    private func externalTriggerMetadata(
        from notification: Notification,
        expectedSources: Set<AppCommandSource>
    ) -> ExternalTriggerMetadata {
        let userInfo = notification.userInfo ?? [:]
        let rawSource = userInfo[BackgroundAppNotifications.sourceUserInfoKey] as? String
        let parsedSource = rawSource.flatMap(AppCommandSource.init(rawValue:))
        let source = parsedSource ?? .unexpectedExternalTrigger

        if !expectedSources.contains(source) {
            let expected = expectedSources.map(\.rawValue).sorted().joined(separator: ",")
            hotkeyLogger.warning(
                "External trigger source mismatch notification=\(notification.name.rawValue) expected=\(expected) received=\(rawSource ?? "missing")"
            )
        }

        return ExternalTriggerMetadata(
            notificationName: notification.name.rawValue,
            source: source,
            eventID: stringValue(userInfo[BackgroundAppNotifications.eventIDUserInfoKey]),
            senderPID: stringValue(userInfo[BackgroundAppNotifications.senderPIDUserInfoKey]),
            command: stringValue(userInfo[BackgroundAppNotifications.commandUserInfoKey]),
            timestamp: stringValue(userInfo[BackgroundAppNotifications.timestampUserInfoKey])
        )
    }

    private func logExternalTriggerMetadata(_ metadata: ExternalTriggerMetadata, action: String) {
        hotkeyLogger.info(
            "Received external \(action) trigger notification=\(metadata.notificationName) source=\(metadata.source.rawValue) event_id=\(metadata.eventID) sender_pid=\(metadata.senderPID) command=\(metadata.command) timestamp=\(metadata.timestamp)"
        )
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return String(int)
        case let int32 as Int32:
            return String(int32)
        case let double as Double:
            return String(double)
        case let value?:
            return String(describing: value)
        case nil:
            return "missing"
        }
    }
}

private struct ExternalTriggerMetadata {
    let notificationName: String
    let source: AppCommandSource
    let eventID: String
    let senderPID: String
    let command: String
    let timestamp: String
}
