import AppKit
import Foundation

/// Asks an application to do something through Apple Events.
///
/// This is the second way to reach a window, and it exists because the first one
/// does not always work: Accessibility publishes no windows for Chrome or Finder,
/// so a window of theirs can be named but not raised. An application's own
/// scripting interface knows its windows whatever Accessibility says.
///
/// It is not free. macOS asks the user to allow control of each application
/// separately, the request is refused until they do, and an application without a
/// scripting dictionary — most things built on Electron — cannot be asked at all.
/// Every call therefore reports failure rather than throwing, and the caller
/// carries on as it would have without it.
enum ApplicationScripting {
  /// Long enough for a busy application to answer, short enough that a wedged one
  /// does not hold up a window switch.
  private static let timeout = Duration.seconds(3)

  /// Brings the named window of an application to the front.
  static func raiseWindow(titled title: String, bundleIdentifier: String) async -> Bool {
    guard !title.isEmpty else {
      return false
    }

    let source = """
      tell application id "\(escaped(bundleIdentifier))"
        activate
        repeat with candidate in every window
          set found to ""
          try
            set found to (name of candidate) as text
          on error
            try
              set found to (title of candidate) as text
            end try
          end try
          if found is equal to "\(escaped(title))" then
            set index of candidate to 1
            return true
          end if
        end repeat
      end tell
      return false
      """

    return await run(source)
  }

  /// Runs a script off the main actor, and gives up on it rather than waiting for
  /// an application that is not answering. An abandoned script is left to finish on
  /// its own — the alternative is a switcher that stops responding because some
  /// application did.
  private static func run(_ source: String) async -> Bool {
    await withCheckedContinuation { continuation in
      let result = ScriptResult(continuation)

      Task.detached {
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)

        if let error {
          await result.finish(with: false, note: "\(error)")
        } else {
          await result.finish(with: value?.booleanValue ?? false, note: nil)
        }
      }

      Task {
        try? await Task.sleep(for: timeout)
        await result.finish(with: false, note: "timed out")
      }
    }
  }

  /// Quotes are what an AppleScript string literal cannot carry unescaped.
  private static func escaped(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}

/// Delivers the first of the script and its timeout, and ignores whichever loses.
private actor ScriptResult {
  private var continuation: CheckedContinuation<Bool, Never>?
  private let logger = AppLogger(debugMode: true, category: .app)

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func finish(with value: Bool, note: String?) {
    guard let continuation else {
      return
    }

    if let note {
      logger.debug("Apple Events: \(note)")
    }

    self.continuation = nil
    continuation.resume(returning: value)
  }
}
