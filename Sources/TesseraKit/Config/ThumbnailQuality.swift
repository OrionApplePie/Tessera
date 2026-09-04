import CoreGraphics
import Foundation

/// How many pixels a thumbnail is captured with.
///
/// The tile is a fraction of the screen, so a capture made for the tile alone goes
/// soft the moment the overlay fills a large display: measured, the largest tile
/// asked for 688 pixels across, against the 1280 a screen of that size deserves.
/// The two steps here are the honest trade — pixels against the memory every
/// window's picture takes while the switcher is running.
enum ThumbnailQuality: Equatable, Sendable, CaseIterable {
  /// The default: exactly what the largest tile can show, and nothing spent on
  /// pixels no one sees. Measured, a list of two dozen windows costs about 60 MB
  /// this way — against a gigabyte at `hd`, which is the whole reason this step
  /// exists.
  case tile
  /// A picture about as wide as an HD frame: sharp on a screen-filling overlay,
  /// and about ten megabytes a window.
  case hd
  /// Half again as wide, for a screen where the tiles are large enough to read
  /// documents in. Costs about twice the memory, so it goes with a shorter list.
  case max

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "tile", "default", "fit":
      self = .tile
    case "hd", "1280":
      self = .hd
    case "max", "1920", "high", "sharp":
      self = .max
    default:
      throw ThumbnailQualityError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .tile:
      return "tile"
    case .hd:
      return "hd"
    case .max:
      return "max"
    }
  }

  /// The long side a capture aims for, in pixels.
  var longSide: CGFloat {
    switch self {
    case .tile:
      return 0
    case .hd:
      return 1280
    case .max:
      return 1920
    }
  }

  /// What to multiply a piece of a window by to reach that many pixels, never less
  /// than the screen's own scale — a capture below it would be softer than what the
  /// display already shows — and never more than needed.
  func scale(forCrop crop: CGSize, onScreenScale screenScale: CGFloat) -> CGFloat {
    let longest = Swift.max(crop.width, crop.height)

    guard longest > 0, longSide > 0 else {
      return screenScale
    }

    return Swift.max(screenScale, longSide / longest)
  }
}

enum ThumbnailQualityError: Error, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      let names = ThumbnailQuality.allCases.map(\.name).joined(separator: ", ")
      return "unknown thumbnail quality \"\(text)\"; expected \(names)"
    }
  }
}
