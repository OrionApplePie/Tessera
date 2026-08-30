import CoreGraphics
import Foundation

/// How a window is recognised between runs. `CGWindowID` is reused by the window
/// server, so it cannot serve: the application and the window's title can.
struct WindowSignature: Hashable, Sendable, Comparable {
  let applicationName: String
  let title: String

  static func < (first: WindowSignature, second: WindowSignature) -> Bool {
    if first.applicationName != second.applicationName {
      return first.applicationName < second.applicationName
    }

    return first.title < second.title
  }
}

/// Remembers windows that ignored an activation.
///
/// A tray application's closed window looks exactly like a window on another
/// Space, and nothing about the window itself tells them apart. What does tell
/// them apart is what happens when you ask the window to come forward: a real one
/// arrives, a leftover does not. That verdict is worth keeping, because it is a
/// property of the application rather than of the session.
///
/// The file is plain text rather than TOML because the config parser here has no
/// arrays, and one line per window is easier to edit by hand than any encoding of
/// a list into key-value pairs would be.
@MainActor
final class LearnedWindowStore {
  static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/tessera/learned-windows.txt")

  private let fileURL: URL
  private let logger: AppLogger
  private var signatures: Set<WindowSignature> = []

  init(fileURL: URL = LearnedWindowStore.defaultFileURL, debugMode: Bool = false) {
    self.fileURL = fileURL
    self.logger = AppLogger(debugMode: debugMode, category: .config)
    self.signatures = Self.load(from: fileURL, logger: logger)
  }

  func contains(_ signature: WindowSignature) -> Bool {
    signatures.contains(signature)
  }

  func learn(_ signature: WindowSignature) {
    guard signatures.insert(signature).inserted else {
      return
    }

    logger.info(
      "\(signature.applicationName) did not come forward when activated; hiding "
        + "that window. Delete its line from \(fileURL.path) to give it another chance."
    )
    save()
  }

  func forget(_ signature: WindowSignature) {
    guard signatures.remove(signature) != nil else {
      return
    }

    logger.info("\(signature.applicationName) came forward again; listing it once more")
    save()
  }

  // MARK: - File format

  /// One window per line, application and title separated by a tab, `#` starting a
  /// comment. A line that does not parse is skipped rather than discarding the
  /// rest of the file: this is a file people are invited to edit.
  nonisolated static func parse(_ text: String) -> Set<WindowSignature> {
    var signatures: Set<WindowSignature> = []

    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard !line.hasPrefix("#") else {
        continue
      }

      let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        continue
      }

      let applicationName = parts[0].trimmingCharacters(in: .whitespaces)
      let title = String(parts[1])
      guard !applicationName.isEmpty, !title.isEmpty else {
        continue
      }

      signatures.insert(WindowSignature(applicationName: applicationName, title: title))
    }

    return signatures
  }

  nonisolated static func serialize(_ signatures: Set<WindowSignature>) -> String {
    let header = """
      # Windows that did not come forward when Tessera activated them, so they are
      # left out of the switcher. Written by Tessera; edit or delete freely.
      # One window per line: application, a tab, then the window title.

      """

    let lines = signatures.sorted().map { "\($0.applicationName)\t\($0.title)" }
    return ([header] + lines).joined(separator: "\n") + "\n"
  }

  nonisolated private static func load(
    from fileURL: URL,
    logger: AppLogger
  ) -> Set<WindowSignature> {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }

    do {
      return parse(try String(contentsOf: fileURL, encoding: .utf8))
    } catch {
      logger.error("Failed to read \(fileURL.path); starting with nothing learned: \(error)")
      return []
    }
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Self.serialize(signatures).write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      logger.error("Failed to write \(fileURL.path): \(error)")
    }
  }
}
