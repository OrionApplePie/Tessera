import Foundation
import OSLog

enum LogCategory: String {
  case app
  case config
  case overlay
  case preview
  case capture
  case trigger
}

struct AppLogger {
  private static let subsystem = "com.tessera"

  private let logger: Logger
  private let debugMode: Bool

  init(debugMode: Bool, category: LogCategory) {
    self.logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    self.debugMode = debugMode
  }

  func debug(_ message: @autoclosure () -> String) {
    guard debugMode else {
      return
    }

    let text = message()
    logger.debug("\(text, privacy: .public)")
  }

  func info(_ message: @autoclosure () -> String) {
    let text = message()
    logger.info("\(text, privacy: .public)")
  }

  func warning(_ message: @autoclosure () -> String) {
    let text = message()
    logger.warning("\(text, privacy: .public)")
  }

  func error(_ message: @autoclosure () -> String) {
    let text = message()
    logger.error("\(text, privacy: .public)")
  }
}
