import Foundation

/// What the arrows count in.
///
/// The map has two grains — Spaces and the windows inside them — and only one of
/// them can be what an arrow means.
enum OverlayArrowStep: Equatable, Sendable, CaseIterable {
  /// The arrows move from Space to Space, and the windows of a Space are reached
  /// with the cycling key instead. A Space with one window needs no cycling at all,
  /// which is most of them, so the arrows stop catching on Spaces holding several.
  case spaces
  /// The arrows walk every window in turn, crossing into the next Space when a
  /// Space runs out.
  case windows

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "spaces", "space", "groups":
      self = .spaces
    case "windows", "window", "tiles":
      self = .windows
    default:
      throw OverlayArrowStepError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .spaces:
      return "spaces"
    case .windows:
      return "windows"
    }
  }
}

enum OverlayArrowStepError: Error, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      let names = OverlayArrowStep.allCases.map(\.name).joined(separator: ", ")
      return "unknown arrow step \"\(text)\"; expected \(names)"
    }
  }
}
