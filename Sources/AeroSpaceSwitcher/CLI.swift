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
            postExternalSwitcherNotification(
                command: "show",
                name: BackgroundAppNotifications.showSwitcher,
                source: .externalShowCommand
            )

        case "toggle":
            postExternalSwitcherNotification(
                command: "toggle",
                name: BackgroundAppNotifications.toggleSwitcher,
                source: .externalToggleCommand
            )

        default:
            throw CLIError.invalidArguments("Unknown command: \(arguments[0])")
        }
    }

    private static func postExternalSwitcherNotification(
        command: String,
        name: Notification.Name,
        source: OverlayOpenSource
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

    static func printUsageAndExit() -> Never {
        let usage = """
        AeroSpaceSwitcher - AeroSpace helper CLI and native overlay

        Commands:
          workspaces          List all workspaces and mark focused ones
          windows             List windows with workspace, app and title
          switch <id>         Switch to workspace <id>
          overview            Print a grouped text overview of workspaces and windows
          gui                 Run the background menu bar utility
          show                Ask the running background app to show the switcher
          toggle              Ask the running background app to toggle the switcher
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

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}
