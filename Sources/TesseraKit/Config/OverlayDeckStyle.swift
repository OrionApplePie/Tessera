import Foundation

/// How the cards of one tessera are drawn — the windows of one Space.
///
/// A Space of several windows has to say two things at once: which window is
/// chosen, and that there are others behind it. The three styles answer that
/// differently — one shows the others, two count them and differ in what stepping
/// through them looks like.
enum OverlayDeckStyle: Equatable, Sendable, CaseIterable {
  /// Each card peeks out from behind the one in front of it by a strip down its
  /// side: the windows of a Space are all visible at once, at the cost of a wider
  /// group and a busier map.
  case fan
  /// The default. One card, squarely on top of the rest, with a mark saying how
  /// many there are. A Space takes the room of one window however many it holds,
  /// and stepping through it turns the card over rather than moving the stack.
  case stack
  /// One card, like `stack`, but the next one is simply there: no turn, no motion.
  /// Dealt rather than flipped — for a map that should sit still while it is read.
  case deal

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "fan", "spread", "peek":
      self = .fan
    case "stack", "pile", "single":
      self = .stack
    case "deal", "plain", "swap":
      self = .deal
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
    case .deal:
      return "deal"
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
