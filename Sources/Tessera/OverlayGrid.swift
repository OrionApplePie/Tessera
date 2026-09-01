import Foundation

/// Keyboard navigation over the overlay's wrapped grid of tiles.
///
/// Kept apart from the SwiftUI view so the movement rules can be tested without
/// a window on screen.
enum OverlayGrid {
  enum Direction {
    case left
    case right
    case up
    case down
  }

  /// One column count for the whole overlay, so tiles line up down the sections
  /// instead of every section picking its own width. A row never holds more than
  /// `maximum` tiles, which is what keeps the panel narrower than the screen.
  /// Where a panel of `size` sits on a screen whose usable area is `usable`.
  ///
  /// `nil` says the screen is not known well enough to place anything, which is
  /// the caller's cue to fall back to `NSWindow.center()`. Note that `usable` is
  /// not anchored at the origin on a second display: centring by width and height
  /// alone would put the panel on whichever screen happens to contain that point.
  static func placement(for size: CGSize, in usable: CGRect) -> CGRect? {
    guard usable.width > 0, usable.height > 0, size.width > 0, size.height > 0 else {
      return nil
    }

    return CGRect(
      x: usable.midX - size.width / 2,
      y: usable.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func columnCount(forSectionSizes sizes: [Int], maximum: Int) -> Int {
    max(1, min(sizes.max() ?? 0, max(1, maximum)))
  }

  /// Flat tile indices laid out row by row, one section after another. A section
  /// always starts a new row, which is what makes a section boundary invisible to
  /// the movement rules below: it is simply the next row down.
  static func rows(forSectionSizes sizes: [Int], maximum: Int) -> [[Int]] {
    let columns = columnCount(forSectionSizes: sizes, maximum: maximum)
    var rows: [[Int]] = []
    var next = 0

    for size in sizes where size > 0 {
      var remaining = size

      while remaining > 0 {
        let taken = min(columns, remaining)
        rows.append(Array(next..<(next + taken)))
        next += taken
        remaining -= taken
      }
    }

    return rows
  }

  /// Where the highlight sits when the overlay opens: on the window you are in.
  ///
  /// The accent fill already says which one that is, so starting the highlight
  /// there makes the two marks agree and gives the arrow keys an obvious origin —
  /// you move away from where you are, rather than from wherever the list happens
  /// to begin.
  static func initialIndex(for targets: [OverlayTarget]) -> Int {
    targets.firstIndex { $0.window?.isActive == true } ?? 0
  }

  /// What a letter is matched against.
  enum MatchField {
    case applicationName
    case windowTitle
  }

  /// The next tile whose name starts with `character`, wrapping around the list.
  ///
  /// Pressing the same letter again moves on to the next match, so a letter walks
  /// its own windows rather than always landing on the first of them. The search
  /// starts after the current tile for that reason.
  ///
  /// `nil` when no window carries that letter in that field, so the caller can try
  /// another reading of the same key press — or the same reading against the other
  /// field.
  static func index(
    from index: Int,
    matching character: Character,
    in tiles: [WindowTileModel],
    field: MatchField
  ) -> Int? {
    guard !tiles.isEmpty else {
      return nil
    }

    let current = min(max(index, 0), tiles.count - 1)
    let prefix = String(character).lowercased()

    let matches = tiles.indices.filter { position in
      let name =
        field == .applicationName
        ? tiles[position].displayAppName : tiles[position].displayTitle

      return name.lowercased().hasPrefix(prefix)
    }

    guard !matches.isEmpty else {
      return nil
    }

    return matches.first { $0 > current } ?? matches[0]
  }

  /// Left and right walk the tiles in reading order and wrap around the ends,
  /// crossing section boundaries as if the list were flat. Up and down move one
  /// row — into the neighbouring section when that is what is above or below — and
  /// stop at the very top and bottom: wrapping vertically over rows of different
  /// widths teleports the highlight somewhere the eye cannot follow.
  ///
  /// A shorter target row keeps the highlight in its last column rather than
  /// leaving it nowhere.
  static func index(from index: Int, moving direction: Direction, rows: [[Int]]) -> Int {
    let tileCount = rows.reduce(0) { $0 + $1.count }
    guard tileCount > 0 else {
      return 0
    }

    let current = min(max(index, 0), tileCount - 1)
    guard let row = rows.firstIndex(where: { $0.contains(current) }) else {
      return current
    }

    switch direction {
    case .left:
      return (current - 1 + tileCount) % tileCount

    case .right:
      return (current + 1) % tileCount

    // Wrapping, like left and right, because the alternative is a dead end: holding
    // an arrow at the last row left the overlay looking as though it had stopped
    // responding, which is exactly what it was reported as.
    case .up:
      let above = (row - 1 + rows.count) % rows.count
      return rows[above][min(current - rows[row][0], rows[above].count - 1)]

    case .down:
      let below = (row + 1) % rows.count
      return rows[below][min(current - rows[row][0], rows[below].count - 1)]
    }
  }
}
