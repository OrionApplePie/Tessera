import AppKit
import Foundation

@main
@MainActor
struct AeroSpaceSwitcherApp {
    private static var appCoordinator: AppCoordinator?
    private static var singleInstanceLock: SingleInstanceLock?
    private static let appLogger = AppLogger(debugMode: true, category: .app)

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let client = AeroSpaceClient()

        if arguments.first == "run" {
            runBackgroundApp()
        }

        do {
            try CLI.run(arguments: arguments, client: client)
        } catch {
            appLogger.error("CLI command failed: \(error)")
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runBackgroundApp() -> Never {
        let application = NSApplication.shared
        let config = AppConfigLoader().load()
        let coordinator = AppCoordinator(config: config)
        let logger = AppLogger(debugMode: config.debugMode, category: .app)
        let lock = SingleInstanceLock(debugMode: config.debugMode)

        do {
            guard try lock.tryAcquire() else {
                logger.info("Background app already running; exiting duplicate run")
                exit(0)
            }
        } catch {
            logger.error("Failed to acquire single-instance lock: \(error)")
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

        logger.info("Starting background app")
        logger.debug("Debug logging enabled")

        singleInstanceLock = lock
        appCoordinator = coordinator
        application.delegate = coordinator
        application.setActivationPolicy(.accessory)
        application.run()

        singleInstanceLock?.release()
        singleInstanceLock = nil
        exit(0)
    }
}
