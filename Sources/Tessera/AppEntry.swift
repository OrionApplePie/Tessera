import AppKit
import Foundation

@main
@MainActor
struct TesseraApp {
  private static var appCoordinator: AppCoordinator?
  private static var singleInstanceLock: SingleInstanceLock?
  private static let appLogger = AppLogger(debugMode: true, category: .app)

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let config = AppConfigLoader().load()

    if arguments.first == "run" {
      runBackgroundApp(config: config)
    }

    do {
      try CLI.run(arguments: arguments, config: config)
    } catch {
      appLogger.error("CLI command failed: \(error)")
      fputs("Error: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func runBackgroundApp(config: AppConfig) -> Never {
    let application = NSApplication.shared
    let coordinator = AppCoordinator(config: config)
    let logger = AppLogger(debugMode: config.debugMode, category: .app)
    let lock = SingleInstanceLock(debugMode: config.debugMode)

    do {
      guard try lock.tryAcquire() else {
        logger.info("Background app already running; exiting duplicate run")
        // The lock makes a duplicate `run` a no-op. Say so on stdout, otherwise a
        // second launch looks like a launch that silently failed.
        print("Tessera is already running. Use `tessera restart` to replace it.")
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
