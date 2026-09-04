import Foundation

/// Starts another copy of this executable.
///
/// Shared by `tessera restart` and by the settings window, which both need a
/// running background app replaced rather than a second one started.
enum BackgroundAppLauncher {
  static func launch(arguments: [String]) throws {
    guard let executableURL = Bundle.main.executableURL else {
      throw CLIError.commandFailed("Unable to resolve executable URL")
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    // Detach the child's stdio, otherwise the invoking shell keeps waiting on the
    // inherited pipes and the command never returns.
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try process.run()
  }

  /// Asks a separate process to replace this one: it posts the quit notification,
  /// waits for the single-instance lock to be free, and starts a fresh app. Doing
  /// that from inside the app that is quitting would mean waiting for itself.
  static func requestRestart() throws {
    try launch(arguments: ["restart"])
  }
}
