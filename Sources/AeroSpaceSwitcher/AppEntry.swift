import AppKit
import Foundation

@main
@MainActor
struct AeroSpaceSwitcherApp {
    private static var appCoordinator: AppCoordinator?
    private static let appLogger = AppLogger(debugMode: true, category: .app)

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let client = AeroSpaceClient()

        if arguments.first == "gui" {
            runGUI()
        }

        do {
            try CLI.run(arguments: arguments, client: client)
        } catch {
            appLogger.error("CLI command failed: \(error)")
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runGUI() -> Never {
        let application = NSApplication.shared
        let config = AppConfigLoader().load()
        let coordinator = AppCoordinator(config: config)
        let logger = AppLogger(debugMode: config.debugMode, category: .app)

        logger.info("Starting background app")
        logger.debug("Debug logging enabled")

        appCoordinator = coordinator
        application.delegate = coordinator
        application.setActivationPolicy(.accessory)
        application.run()

        exit(0)
    }
}
