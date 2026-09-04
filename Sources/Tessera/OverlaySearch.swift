import Foundation

/// What typing at the map does.
///
/// Two answers, and the difference is whether letters accumulate. One letter that
/// walks the windows of an application is the older and faster of the two: nothing
/// to read, nothing to clear, and the same key again goes to the next window of
/// that name. A query that builds up finds a window nothing else would — by a word
/// in its title, by the desktop it is on — at the cost of a line to read and a
/// state to get out of.
enum OverlaySearch: Equatable, Sendable, CaseIterable {
  /// The default. A letter moves to the next window whose application starts with
  /// it, or — when no application does — whose title does. Pressing it again moves
  /// to the next one, so a letter walks its own windows.
  case letter
  /// Letters accumulate into a query, scored against the application, the title and
  /// the heading of the Space, and the best match is chosen as you type.
  case fuzzy

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "letter", "initial", "jump":
      self = .letter
    case "fuzzy", "query", "search":
      self = .fuzzy
    default:
      throw OverlaySearchError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .letter:
      return "letter"
    case .fuzzy:
      return "fuzzy"
    }
  }
}

enum OverlaySearchError: Error, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      let names = OverlaySearch.allCases.map(\.name).joined(separator: ", ")
      return "unknown overlay search \"\(text)\"; expected \(names)"
    }
  }
}
