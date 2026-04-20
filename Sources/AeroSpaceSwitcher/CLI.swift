import Foundation

enum CLI {
    static func run(arguments: [String], client: AeroSpaceClient) throws {
        guard !arguments.isEmpty else {
            printUsageAndExit()
        }

        switch arguments[0] {
        case "workspaces":
            let workspaces = try client.listWorkspaces()
            printWorkspaces(workspaces)

        case "windows":
            let windows = try client.listWindows()
            printWindows(windows)

        case "switch":
            guard arguments.count >= 2 else {
                throw CLIError.invalidArguments("Missing workspace id. Usage: AeroSpaceSwitcher switch <id>")
            }
            try client.switchWorkspace(arguments[1])
            print("Switched to workspace \(arguments[1])")

        case "overview":
            let workspaces = try client.listWorkspaces()
            let windows = try client.listWindows()
            printOverview(workspaces: workspaces, windows: windows)

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
            try launchBackgroundApp()

        default:
            throw CLIError.invalidArguments("Unknown command: \(arguments[0])")
        }
    }

    private static func postExternalCommandNotification(
        command: String,
        name: Notification.Name,
        source: AppCommandSource
    ) {
        let logger = AppLogger(debugMode: true, category: .hotkey)
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
        let deadline = Date().addingTimeInterval(5)

        while Date() < deadline {
            let lock = SingleInstanceLock(debugMode: true)
            if try lock.tryAcquire() {
                lock.release()
                logger.info("Background app stopped after \(command) command")
                return
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        throw CLIError.commandFailed("Timed out waiting for background app to stop after \(command)")
    }

    private static func launchBackgroundApp() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw CLIError.commandFailed("Unable to resolve executable URL for restart")
        }

        let logger = AppLogger(debugMode: true, category: .app)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["run"]

        logger.info("Launching background app path=\(executableURL.path)")
        try process.run()
    }

    static func printUsageAndExit() -> Never {
        let usage = """
        AeroSpaceSwitcher - AeroSpace helper CLI and native background switcher

        Commands:
          run                 Start the background menu bar utility if it is not already running
          show                Show the workspace switcher overlay in the running background app
          toggle              Toggle the workspace switcher overlay in the running background app
          quit                Quit the running background app
          restart             Quit the running background app, then start a fresh one

        Debug / utility commands:
          workspaces          List all workspaces and mark focused ones
          windows             List windows with workspace, app and title
          switch <id>         Switch to workspace <id>
          overview            Print a grouped text overview of workspaces and windows
        """
        print(usage)
        exit(0)
    }

    private static func printWorkspaces(_ workspaces: [Workspace]) {
        for workspace in workspaces {
            let marker = workspace.isFocused ? "*" : " "
            print("\(marker) \(workspace.id)")
        }
    }

    private static func printWindows(_ windows: [AeroSpaceWindow]) {
        for window in windows {
            let title = window.title.isEmpty ? "<untitled>" : window.title
            print("[\(window.workspace)] \(window.appName): \(title)")
        }
    }

    private static func printOverview(workspaces: [Workspace], windows: [AeroSpaceWindow]) {
        let grouped = Dictionary(grouping: windows, by: { $0.workspace })

        for workspace in workspaces {
            let marker = workspace.isFocused ? "*" : " "
            print("\n\(marker) Workspace \(workspace.id)")

            let items = grouped[workspace.id, default: []]
            if items.isEmpty {
                print("  (empty)")
                continue
            }

            for window in items {
                let title = window.title.isEmpty ? "<untitled>" : window.title
                print("  - \(window.appName): \(title)")
            }
        }
    }
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
