import Foundation

/// How the Spaces are arranged on the map.
///
/// Three answers to the same question — how many Spaces stand side by side — and
/// they differ in who decides: the room, the config, or nobody at all.
enum OverlayLayout: Equatable, Sendable, CaseIterable {
  /// The default. Every row length is tried and the one that makes the largest tile
  /// while still fitting the screen wins, with each display's Spaces split into
  /// rows of as equal a length as they divide into. Two displays holding one Space
  /// each therefore get one tile above another, as large as the room allows.
  case fitted
  /// The row is as long as `overlay_columns` says, and a display's Spaces still
  /// keep to their own rows. Predictable: the map has the same shape whatever is
  /// open.
  case rows
  /// No bands at all: the Spaces run one after another and wrap when the row is
  /// full, whichever display they belong to. The row length is chosen the way
  /// `fitted` chooses it — by what makes the largest tile — so this is the most
  /// compact of the three, and the only one that does not say where a window is by
  /// where it sits.
  case flow

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "fitted", "auto", "fill":
      self = .fitted
    case "rows", "fixed", "columns":
      self = .rows
    case "flow", "continuous", "none":
      self = .flow
    default:
      throw OverlayLayoutError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .fitted:
      return "fitted"
    case .rows:
      return "rows"
    case .flow:
      return "flow"
    }
  }

  /// Whether a display's Spaces keep to their own rows.
  var isBanded: Bool { self != .flow }
}

enum OverlayLayoutError: Error, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      let names = OverlayLayout.allCases.map(\.name).joined(separator: ", ")
      return "unknown overlay layout \"\(text)\"; expected \(names)"
    }
  }
}
