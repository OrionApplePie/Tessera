import Foundation

/// What the overlay's close shortcut does to the highlighted window.
enum CloseAction: Equatable, Sendable {
  /// Quits the owning application, the way ⌘Q would. An application that keeps
  /// running with its window closed — most things that live in the menu bar — is
  /// gone for good rather than left behind with a window nobody can reach.
  case quitApplication
  /// Presses the window's own close button, leaving the application running.
  case closeWindow

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "quit", "application", "app":
      self = .quitApplication
    case "window", "close":
      self = .closeWindow
    default:
      throw CloseActionError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .quitApplication:
      return "quit"
    case .closeWindow:
      return "window"
    }
  }
}

enum CloseActionError: Error, Equatable, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      return "\"\(text)\" is not a close action; expected quit or window"
    }
  }
}
