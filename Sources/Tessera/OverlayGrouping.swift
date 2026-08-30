import Foundation

/// What the overlay draws a heading for.
///
/// The two axes are independent: displays can be told apart without splitting
/// their Spaces, and Spaces can be split without naming the display they are on.
struct OverlayGrouping: OptionSet, Sendable {
  let rawValue: Int

  static let displays = OverlayGrouping(rawValue: 1 << 0)
  static let spaces = OverlayGrouping(rawValue: 1 << 1)

  private static let byName: [String: OverlayGrouping] = [
    "display": .displays,
    "displays": .displays,
    "space": .spaces,
    "spaces": .spaces,
  ]

  /// The canonical spelling, which the config also accepts verbatim.
  var name: String {
    var parts: [String] = []

    if contains(.displays) {
      parts.append("displays")
    }
    if contains(.spaces) {
      parts.append("spaces")
    }

    return parts.isEmpty ? "none" : parts.joined(separator: "+")
  }

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Parses `displays`, `spaces`, `displays+spaces` or `none`.
  init(parsing text: String) throws {
    let tokens =
      text
      .split(whereSeparator: { $0 == "+" || $0 == "," })
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

    guard !tokens.isEmpty, !tokens.contains(where: \.isEmpty) else {
      throw OverlayGroupingError.unknown(text)
    }

    // "none" is what someone turning grouping off would write, "flat" describes
    // the result. Either way it stands alone: "none+spaces" is a contradiction.
    if tokens.contains("none") || tokens.contains("flat") {
      guard tokens.count == 1 else {
        throw OverlayGroupingError.unknown(text)
      }

      self = []
      return
    }

    var grouping: OverlayGrouping = []
    for token in tokens {
      guard let part = Self.byName[token] else {
        throw OverlayGroupingError.unknown(token)
      }

      grouping.insert(part)
    }

    self = grouping
  }
}

enum OverlayGroupingError: Error, Equatable, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      return "\"\(text)\" is not a grouping; expected displays, spaces, displays+spaces or none"
    }
  }
}
