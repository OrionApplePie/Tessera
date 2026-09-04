import Foundation

/// How the Spaces are arranged on the map.
///
/// Three answers to the same question — how many Spaces stand side by side — and
/// they differ in who decides: the room, the config, or nobody at all.
enum OverlayLayout: Equatable, Sendable, CaseIterable {
  /// Every row length is tried and the one that makes the largest tile while still
  /// fitting the screen wins, with each display's Spaces split into rows of as
  /// equal a length as they divide into. Two displays holding one Space each
  /// therefore get one tile above another, as large as the room allows.
  case fitted
  /// The row is as long as `overlay_columns` says, and a display's Spaces still
  /// keep to their own rows. Predictable: the map has the same shape whatever is
  /// open.
  case rows
  /// The default. No bands at all: the Spaces run one after another and wrap when
  /// the row is full, whichever display they belong to — in the order the displays
  /// are actually arranged, so a monitor standing above the laptop comes first. The
  /// row length is chosen the way `fitted` chooses it, by what makes the largest
  /// tile, which makes this the most compact of the four: nothing is spent on
  /// keeping a short band on a row of its own. The trade is that where a tile sits
  /// no longer says which display its window is on — the heading does.
  case flow
  /// The row length follows from how many Spaces there are: a map of four is two
  /// by two, one of nine is three by three, and the tile is whatever that leaves
  /// room for. Where `fitted` asks what makes the largest tile and takes it — two
  /// Spaces filling a 27-inch screen with two enormous cards — this keeps the map
  /// square, so a map of two reads as a map rather than as a poster, and every map
  /// has roughly the same shape whatever is open. The cell budget still caps it.
  case count

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "fitted", "auto", "fill":
      self = .fitted
    case "rows", "fixed", "columns":
      self = .rows
    case "flow", "continuous", "none":
      self = .flow
    case "count", "square", "adaptive":
      self = .count
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
    case .count:
      return "count"
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
