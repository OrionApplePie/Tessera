import Foundation

/// How the windows of one Space are stacked in its group.
///
/// A Space of several windows has to say two things at once: which window is
/// chosen, and that there are others behind it. The two styles answer that
/// differently — one shows the others, the other counts them.
enum OverlayDeckStyle: Equatable, Sendable, CaseIterable {
  /// Each card peeks out from behind the one in front of it by a strip down its
  /// side: the windows of a Space are all visible at once, at the cost of a wider
  /// group and a busier map.
  case fan
  /// The default. One card, squarely on top of the rest, with a mark saying how
  /// many there are. A Space takes the room of one window however many it holds,
  /// and stepping through it turns the card over rather than moving the stack.
  case stack

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "fan", "spread", "peek":
      self = .fan
    case "stack", "pile", "single":
      self = .stack
    default:
      throw OverlayDeckStyleError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .fan:
      return "fan"
    case .stack:
      return "stack"
    }
  }
}

enum OverlayDeckStyleError: Error, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      let names = OverlayDeckStyle.allCases.map(\.name).joined(separator: ", ")
      return "unknown deck style \"\(text)\"; expected \(names)"
    }
  }
}
