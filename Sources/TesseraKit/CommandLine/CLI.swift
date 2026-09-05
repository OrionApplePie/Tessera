import CoreGraphics
import Foundation

enum CLI {
  /// How long `quit` and `restart` wait for the background app to let go of the
  /// single-instance lock, and how often they look.
  private static let stopDeadline: TimeInterval = 5
  private static let stopPollInterval: TimeInterval = 0.1
  /// How far the run loop is pumped at a time while an async command finishes.
  /// Short enough that the command returns promptly, long enough not to spin.
  private static let runLoopStep: TimeInterval = 0.01

  @MainActor
  static func run(arguments: [String], config: AppConfig) throws {
    guard let command = arguments.first else {
      printUsageAndExit()
    }

    if try runWindowCommand(command, arguments: arguments, config: config) {
      return
    }

    if try runBackgroundAppCommand(command) {
      return
    }

    throw CLIError.invalidArguments("Unknown command: \(command)")
  }

  /// Commands this process answers itself, by looking at the windows.
  @MainActor
  private static func runWindowCommand(
    _ command: String,
    arguments: [String],
    config: AppConfig
  ) throws -> Bool {
    switch command {
    case "windows":
      try runOnMainActor { try await listWindows(config: config) }

    case "focus":
      guard arguments.count >= 2, let windowID = CGWindowID(arguments[1]) else {
        throw CLIError.invalidArguments("Missing or invalid window id. Usage: tessera focus <id>")
      }
      try runOnMainActor { try await focusWindow(windowID, config: config) }

    case "permissions":
      try runOnMainActor { printPermissions(config: config) }

    case "space":
      guard arguments.count >= 2 else {
        throw CLIError.invalidArguments(
          "Missing action. Usage: tessera space list|add|close [index]")
      }
      try runOnMainActor {
        try await runSpace(
          arguments[1], index: arguments.count > 2 ? Int(arguments[2]) : nil,
          config: config)
      }

    default:
      return false
    }

    return true
  }

  /// Commands that are a message to the background app, not work done here.
  private static func runBackgroundAppCommand(_ command: String) throws -> Bool {
    switch command {
    case "show":
      postExternalCommandNotification(
        command: "show",
        name: BackgroundAppNotifications.showSwitcher,
        source: .externalShowCommand
      )

    case "toggle":
      postExternalCommandNotification(
        command: "toggle",
        name: BackgroundAppNotifications.toggleSwitcher,
        source: .externalToggleCommand
      )

    case "settings":
      postExternalCommandNotification(
        command: "settings",
        name: BackgroundAppNotifications.openSettings,
        source: .externalSettingsCommand
      )

    case "quit":
      postExternalCommandNotification(
        command: "quit",
        name: BackgroundAppNotifications.quitApp,
        source: .externalQuitCommand
      )
      try waitForBackgroundAppToStop(command: "quit")

    case "restart":
      postExternalCommandNotification(
        command: "restart",
        name: BackgroundAppNotifications.quitApp,
        source: .externalRestartCommand
      )
      try waitForBackgroundAppToStop(command: "restart")
      try BackgroundAppLauncher.launch(arguments: ["run"])

    default:
      return false
    }

    return true
  }

  // MARK: - Space commands

  /// `space list`, `space add` and `space close`, on the display in use — the one
  /// showing the active Space, which is where the overlay opens too.
  ///
  /// Adding and closing go through Mission Control, so both need Accessibility and
  /// both show it for about a second. Which Space is which is read from the window
  /// server, so all three need `use_private_space_api` on; without it there is no
  /// way to say what a display is showing, and guessing would close the wrong
  /// desktop.
  @MainActor
  private static func runSpace(_ action: String, index: Int?, config: AppConfig) async throws {
    let query = SpaceQuery(enabled: config.usesPrivateSpaceAPI, debugMode: config.debugMode)

    guard let displayID = query.activeDisplay() else {
      throw CLIError.commandFailed(
        "Cannot tell which display is in use; space commands need use_private_space_api = true")
    }

    switch action {
    case "list":
      listSpaces(on: displayID, among: query)

    case "add":
      guard await MissionControl(config: config).addDesktop(on: displayID) else {
        throw CLIError.commandFailed("No desktop appeared on display \(displayID)")
      }

      print("Added a desktop to display \(displayID).")
      listSpaces(on: displayID, among: query)

    case "close":
      try await closeSpace(index, on: displayID, among: query, config: config)

    default:
      throw CLIError.invalidArguments(
        "Unknown action: \(action). Usage: tessera space list|add|close [index]")
    }
  }

  /// Closes one Space by its index, or the one the display is showing when no index
  /// is given.
  @MainActor
  private static func closeSpace(
    _ index: Int?,
    on displayID: CGDirectDisplayID,
    among query: SpaceQuery,
    config: AppConfig
  ) async throws {
    guard let target = index ?? currentSpaceIndex(on: displayID, among: query) else {
      throw CLIError.commandFailed("Cannot tell which Space display \(displayID) is showing")
    }

    guard await MissionControl(config: config).closeSpace(at: target, on: displayID) else {
      throw CLIError.commandFailed("Space \(target) of display \(displayID) was not closed")
    }

    print("Closed Space \(target) of display \(displayID).")
  }

  /// One display's Spaces, in the order the window server keeps them — which is the
  /// order Mission Control shows them in, so these indexes are what `space close`
  /// takes.
  @MainActor
  private static func listSpaces(on displayID: CGDirectDisplayID, among query: SpaceQuery) {
    let showing = query.currentSpaces()[displayID]

    for (index, space) in (query.orderedSpaces()[displayID] ?? []).enumerated() {
      let kind = space.isFullscreen ? "fullscreen" : "desktop"
      let mark = space.id == showing ? " <- showing" : ""

      print("\(index)  \(kind)  id \(space.id)\(mark)")
    }
  }

  /// Where the Space a display is showing sits in that display's list.
  @MainActor
  private static func currentSpaceIndex(
    on displayID: CGDirectDisplayID,
    among query: SpaceQuery
  ) -> Int? {
    guard let current = query.currentSpaces()[displayID] else {
      return nil
    }

    return query.orderedSpaces()[displayID]?.firstIndex { $0.id == current }
  }

  // MARK: - Window commands

  @MainActor
  private static func listWindows(config: AppConfig) async throws {
    let snapshot = try await WindowListService(config: config).snapshot()
    // No Space grouping here: a one-shot command has watched nothing and learned
    // nothing. Displays it can still tell apart.
    let windows = WindowListService.ordered(
      snapshot.windows,
      displayOrder: snapshot.displayOrder,
      limit: config.maxWindows
    )

    guard !windows.isEmpty else {
      print("No switchable windows found.")
      print("If this is unexpected, check Screen Recording permission: tessera permissions")
      return
    }

    for window in windows {
      let title = window.title.isEmpty ? "<untitled>" : window.title
      let display = snapshot.displayNames[window.displayID] ?? "display \(window.displayID)"
      // Reaching these costs a Space switch or an unminimize, so say which is which.
      let location =
        window.isMinimized ? ", minimized" : (window.isOnScreen ? "" : ", off-screen")
      print("\(window.id)\t\(window.appName): \(title)\t(\(display)\(location))")
    }
  }

  @MainActor
  private static func focusWindow(_ windowID: CGWindowID, config: AppConfig) async throws {
    let windows = try await WindowListService(config: config).snapshot().windows

    guard let window = windows.first(where: { $0.id == windowID }) else {
      throw CLIError.commandFailed("No switchable window with id \(windowID)")
    }

    let tile = WindowTileModel(
      id: window.id,
      appName: window.appName,
      title: window.title,
      processID: window.processID,
      isActive: false,
      isMinimized: window.isMinimized,
      displayID: window.displayID,
      spaceIndex: nil,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )

    try WindowActivator(config: config).activate(tile)
    print("Focused \(tile.displayAppName): \(tile.displayTitle)")
  }

  @MainActor
  private static func printPermissions(config: AppConfig) {
    let screenRecording = CGPreflightScreenCaptureAccess()
    let accessibility = WindowActivator(config: config).isAccessibilityTrusted

    let spaces = SpaceQuery(enabled: config.usesPrivateSpaceAPI, debugMode: false).availability

    print("Screen Recording : \(screenRecording ? "granted" : "NOT granted")")
    print("Accessibility    : \(accessibility ? "granted" : "NOT granted")")
    print("Spaces (private) : \(spaces.summary)")

    if !spaces.isComplete {
      print("")
      print("The window server's own calls are what number the desktops and say")
      print("which Space a window is on. Without them Tessera infers both from")
      print("what appears on screen together, which is right for a Space you have")
      print("visited and unknown for one you have not.")

      for name in spaces.found.keys.sorted() {
        print("  \(spaces.found[name] == true ? "found  " : "MISSING") \(name)")
      }
    }

    if !screenRecording {
      print("")
      print("Screen Recording is required to list windows and capture thumbnails.")
      print("Grant it in System Settings > Privacy & Security > Screen Recording.")
    }

    if !accessibility {
      print("")
      print("Accessibility is required to raise a specific window.")
      print("Without it Tessera can only bring the owning application forward.")
      print("Grant it in System Settings > Privacy & Security > Accessibility.")
    }
  }

  /// Runs an async main-actor command from the synchronous CLI entry point.
  ///
  /// `main()` stays synchronous because the background app hands control to
  /// `NSApplication.run()`, so async commands are pumped on the main run loop here.
  @MainActor
  private static func runOnMainActor(
    _ body: @escaping @MainActor () async throws -> Void
  ) throws {
    let box = CommandResultBox()

    Task { @MainActor in
      do {
        try await body()
        box.result = .success(())
      } catch {
        box.result = .failure(error)
      }
    }

    while box.result == nil {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(Self.runLoopStep))
    }

    try box.result?.get()
  }

  // MARK: - Background app control

  private static func postExternalCommandNotification(
    command: String,
    name: Notification.Name,
    source: AppCommandSource
  ) {
    let logger = AppLogger(debugMode: true, category: .trigger)
    let userInfo = BackgroundAppNotifications.userInfo(source: source, command: command)

    logger.info("CLI \(command) command started")
    logger.info(
      "Posting distributed notification name=\(name.rawValue) object=\(BackgroundAppNotifications.notificationObject)"
    )
    logger.debug("Distributed notification userInfo=\(userInfo)")

    DistributedNotificationCenter.default().post(
      name: name,
      object: BackgroundAppNotifications.notificationObject,
      userInfo: userInfo
    )

    logger.info("CLI \(command) command finished")
  }

  private static func waitForBackgroundAppToStop(command: String) throws {
    let logger = AppLogger(debugMode: true, category: .app)
    let deadline = Date().addingTimeInterval(Self.stopDeadline)

    while Date() < deadline {
      let lock = SingleInstanceLock(debugMode: true)
      if try lock.tryAcquire() {
        lock.release()
        logger.info("Background app stopped after \(command) command")
        return
      }

      Thread.sleep(forTimeInterval: Self.stopPollInterval)
    }

    throw CLIError.commandFailed(
      "Timed out waiting for background app to stop after \(command)")
  }

  static func printUsageAndExit() -> Never {
    let usage = """
      Tessera - native macOS window switcher

      Commands:
        run                 Start the background menu bar utility if it is not already running
        show                Show the window switcher overlay in the running background app
        toggle              Toggle the window switcher overlay in the running background app
        settings            Open the settings window of the running background app
        quit                Quit the running background app
        restart             Quit the running background app, then start a fresh one

      Debug / utility commands:
        windows             List switchable windows as "<id> <app>: <title>"
        focus <id>          Bring the window with the given id to the front
        permissions         Report Screen Recording and Accessibility permission status
        space list          List the Spaces of the display in use, by index
        space add           Add a desktop to the display in use
        space close [i]     Close Space i, or the one the display in use is showing
      """
    print(usage)
    exit(0)
  }
}

@MainActor
private final class CommandResultBox {
  var result: Result<Void, Error>?
}

enum CLIError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case commandFailed(String)

  var description: String {
    switch self {
    case .invalidArguments(let message):
      return message
    case .commandFailed(let message):
      return message
    }
  }
}
