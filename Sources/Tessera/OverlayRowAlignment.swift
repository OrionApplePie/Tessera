import SwiftUI

/// Where a short row sits under a long one.
///
/// A band of seven Spaces splits into four and three, and the three have to go
/// somewhere. Centred they read as one block, which is why that is the default;
/// left is what you want when the map is read as a list and the eye returns to the
/// same edge every time.
enum OverlayRowAlignment: Equatable, Sendable, CaseIterable {
  case leading
  case center
  case trailing

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "left", "leading", "start":
      self = .leading
    case "center", "centre", "middle":
      self = .center
    case "right", "trailing", "end":
      self = .trailing
    default:
      throw OverlayRowAlignmentError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .leading:
      return "left"
    case .center:
      return "center"
    case .trailing:
      return "right"
    }
  }

  var horizontal: HorizontalAlignment {
    switch self {
    case .leading:
      return .leading
    case .center:
      return .center
    case .trailing:
      return .trailing
    }
  }

  /// The same alignment for the frame the map sits in, so that a left-aligned map
  /// starts at the left edge of the panel rather than at the left edge of its own
  /// widest row.
  var frame: Alignment {
    switch self {
    case .leading:
      return .leading
    case .center:
      return .center
    case .trailing:
      return .trailing
    }
  }
}

enum OverlayRowAlignmentError: Error, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      let names = OverlayRowAlignment.allCases.map(\.name).joined(separator: ", ")
      return "unknown row alignment \"\(text)\"; expected \(names)"
    }
  }
}
