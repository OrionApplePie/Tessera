import Foundation

/// A colour as the config spells it: `#RRGGBB`, or `#RRGGBBAA` when the overlay
/// should let the desktop through.
struct OverlayColor: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  init(parsing text: String) throws {
    var digits = Substring(text.trimmingCharacters(in: .whitespaces))
    if digits.hasPrefix("#") {
      digits = digits.dropFirst()
    }

    guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit) else {
      throw OverlayColorError.malformed(text)
    }

    guard let value = UInt32(digits, radix: 16) else {
      throw OverlayColorError.malformed(text)
    }

    let hasAlpha = digits.count == 8
    let channels = hasAlpha ? value : (value << 8) | 0xFF

    self.init(
      red: Self.channel(channels, shift: 24),
      green: Self.channel(channels, shift: 16),
      blue: Self.channel(channels, shift: 8),
      alpha: Self.channel(channels, shift: 0)
    )
  }

  /// What the config would have to say to produce this colour.
  var hexDescription: String {
    let components = [red, green, blue, alpha].map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
    return "#" + components.map { String(format: "%02X", $0) }.joined()
  }

  private static func channel(_ value: UInt32, shift: UInt32) -> Double {
    Double((value >> shift) & 0xFF) / 255
  }
}

enum OverlayColorError: Error, Equatable, CustomStringConvertible {
  case malformed(String)

  var description: String {
    switch self {
    case .malformed(let text):
      return "\"\(text)\" is not a colour; expected #RRGGBB or #RRGGBBAA"
    }
  }
}
