import AppKit

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
  private let config: AppConfig
  private let logger: AppLogger
  private let triggerLogger: AppLogger
  private lazy var windowCoordinator = WindowCoordinator(config: config)
  private var overlayWindowController: OverlayWindowController?
  private var menuBarController: MenuBarController?
  private var hotkeyController: HotkeyController?
  private var settingsWindowController: SettingsWindowController?
  private var isStopped = false

  init(config: AppConfig) {
    self.config = config
    self.logger = AppLogger(debugMode: config.debugMode, category: .app)
    self.triggerLogger = AppLogger(debugMode: config.debugMode, category: .trigger)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    logger.info("Application did finish launching")

    windowCoordinator.start()
    overlayWindowController = OverlayWindowController(
      windowCoordinator: windowCoordinator,
      closeAfterActivation: config.closeAfterActivation,
      background: config.overlayBackground,
      columns: config.overlayColumns,
      dimsStaleThumbnails: config.dimsStaleThumbnails,
      closeHotkey: config.closeHotkey,
      debugMode: config.debugMode
    )

    if config.showMenuBarIcon {
      menuBarController = MenuBarController(
        windowCoordinator: windowCoordinator,
        showSwitcher: { [weak self] in self?.showOverlay(source: .menuBarAction) },
        refreshNow: { [weak self] in self?.refreshNow() },
        pauseRefresh: { [weak self] in self?.pauseRefresh() },
        resumeRefresh: { [weak self] in self?.resumeRefresh() },
        requestAccessibility: { [weak self] in self?.requestAccessibilityPermission() },
        openSettings: { [weak self] in self?.openSettings() },
        quit: { [weak self] in self?.quit() }
      )
    } else {
      logger.info("Menu bar icon disabled by config")
    }

    if !windowCoordinator.isAccessibilityTrusted {
      logger.warning(
        "Accessibility permission not granted; activation will raise the application but not a specific window"
      )
    }

    registerGlobalHotkey()
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
    windowCoordinator.start()
  }

  func stop() {
    guard !isStopped else {
      return
    }

    isStopped = true
    logger.info("Stopping app coordinator")
    DistributedNotificationCenter.default().removeObserver(self)
    hotkeyController?.stop()
    hotkeyController = nil
    overlayWindowController?.hideOverlay()
    windowCoordinator.stop()
  }

  func pauseRefresh() {
    logger.info("Pausing background refresh")
    windowCoordinator.pauseRefresh()
    menuBarController?.updateRefreshItems()
  }

  func resumeRefresh() {
    logger.info("Resuming background refresh")
    windowCoordinator.resumeRefresh()
    menuBarController?.updateRefreshItems()
  }

  func requestAccessibilityPermission() {
    windowCoordinator.requestAccessibilityPermission()
    menuBarController?.updateRefreshItems()
  }

  func refreshNow() {
    logger.info("Manual preview refresh requested")
    Task { @MainActor [weak self] in
      await self?.windowCoordinator.refreshNow()
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
    logger.debug(
      "Toggle from \(source.rawValue); overlay visible="
        + "\(overlayWindowController?.isOverlayVisible == true)")

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

  /// A hotkey that cannot be registered is reported, not swallowed: the app still
  /// works through the CLI and the menu bar, and the log says why the key is dead.
  func openSettings() {
    logger.info("Opening settings")

    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        config: config,
        configURL: AppConfigLoader.defaultURL,
        debugMode: config.debugMode
      )
    }

    settingsWindowController?.present()
  }

  private func registerGlobalHotkey() {
    guard let binding = config.hotkey else {
      logger.info("Global hotkey disabled by config")
      return
    }

    let controller = HotkeyController(
      binding: binding,
      debugMode: config.debugMode
    ) { [weak self] in
      self?.toggleOverlay(source: .globalHotkey)
    }

    do {
      try controller.start()
      hotkeyController = controller
    } catch {
      logger.error("Failed to register global hotkey \(binding.displayName): \(error)")
    }
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
      selector: #selector(openSettingsNotification(_:)),
      name: BackgroundAppNotifications.openSettings,
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

  @objc private func openSettingsNotification(_ notification: Notification) {
    let metadata = externalTriggerMetadata(
      from: notification,
      expectedSources: [.externalSettingsCommand]
    )
    logExternalTriggerMetadata(metadata, action: "settings")

    openSettings()
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
      triggerLogger.warning(
        "External trigger source mismatch notification=\(notification.name.rawValue) "
          + "expected=\(expected) received=\(rawSource ?? "missing")"
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
    triggerLogger.info(
      "Received external \(action) trigger notification=\(metadata.notificationName) "
        + "source=\(metadata.source.rawValue) event_id=\(metadata.eventID) "
        + "sender_pid=\(metadata.senderPID) command=\(metadata.command) "
        + "timestamp=\(metadata.timestamp)"
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
