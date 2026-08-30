import CoreGraphics
import Foundation

/// What decides the order of the tiles, and therefore what makes one move.
enum WindowOrder: Equatable, Sendable {
  /// Application, then window title. A browser tab switch changes the title and
  /// moves the tile, which is the price of a list that reads alphabetically.
  case title
  /// Application only. Windows of one application keep a fixed order between
  /// themselves whatever happens inside them.
  case application
  /// The order windows were first seen in. Nothing moves; a new window is appended.
  case stable

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "title", "titles":
      self = .title
    case "application", "applications", "app", "apps":
      self = .application
    case "stable", "fixed":
      self = .stable
    default:
      throw WindowOrderError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .title:
      return "title"
    case .application:
      return "application"
    case .stable:
      return "stable"
    }
  }
}

enum WindowOrderError: Error, Equatable, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      return "\"\(text)\" is not a window order; expected title, application or stable"
    }
  }
}

/// Remembers the place each window was given, so a stable order has something to
/// be stable about.
///
/// Places are handed out in the order the windows would have taken alphabetically,
/// so a list that never moves still starts out in a sensible arrangement rather
/// than in whatever order the window server happened to report.
struct WindowOrderRegistry {
  private var sequenceByWindow: [CGWindowID: Int] = [:]
  private var nextSequence = 0

  mutating func sequence(for windows: [WindowInfo]) -> [CGWindowID: Int] {
    let newcomers =
      windows
      .filter { sequenceByWindow[$0.id] == nil }
      .sorted { first, second in
        if first.appName != second.appName {
          return first.appName.localizedStandardCompare(second.appName) == .orderedAscending
        }

        if first.title != second.title {
          return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }

        return first.id < second.id
      }

    for window in newcomers {
      sequenceByWindow[window.id] = nextSequence
      nextSequence += 1
    }

    // A closed window frees its place. A window that comes back has a new id and
    // goes to the end, because the window server gave it a new identity too.
    let live = Set(windows.map(\.id))
    sequenceByWindow = sequenceByWindow.filter { live.contains($0.key) }

    return sequenceByWindow
  }
}
