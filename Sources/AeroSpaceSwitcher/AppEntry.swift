import AppKit
import Foundation

@main
@MainActor
struct AeroSpaceSwitcherApp {
    private static var appCoordinator: AppCoordinator?

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let client = AeroSpaceClient()

        if arguments.first == "gui" {
            runGUI()
        }

        do {
            try CLI.run(arguments: arguments, client: client)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runGUI() -> Never {
        let application = NSApplication.shared
        let config = AppConfigLoader().load()
        let coordinator = AppCoordinator(config: config)

        appCoordinator = coordinator
        application.delegate = coordinator
        application.setActivationPolicy(.accessory)
        application.run()

        exit(0)
    }
}
