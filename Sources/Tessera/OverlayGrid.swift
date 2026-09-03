import CoreGraphics
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

  /// The map's rows, as lists of Space numbers.
  ///
  /// The map is a grid whose cell is a Space, not a window: a row ends where the
  /// display ends, so each screen keeps its own band, and it ends again after
  /// `perRow` Spaces. Nothing is drawn between the bands — a display is where its
  /// Spaces are, which is what makes the map read like the desk the screens stand
  /// on.
  static func spaceRows(ofDisplays displays: [CGDirectDisplayID], perRow: Int) -> [[Int]] {
    var rows: [[Int]] = []
    let limit = max(1, perRow)

    for (index, display) in displays.enumerated() {
      let sameDisplay = rows.last.flatMap { $0.last }.map { displays[$0] == display } ?? false

      if var row = rows.last, sameDisplay, row.count < limit {
        row.append(index)
        rows[rows.count - 1] = row
      } else {
        rows.append([index])
      }
    }

    return rows
  }

  /// Where the highlight goes, on a map whose cells are Spaces.
  ///
  /// Left and right deal through the cards of a Space and then step to the Space
  /// beside it; up and down move to the Space above or below, keeping the column
  /// and landing at the same depth in its deck where there is one. Both wrap: the
  /// map is a loop in each direction, so no arrow ever refuses to move.
  static func index(
    from index: Int,
    moving direction: Direction,
    sizes: [Int],
    rows: [[Int]]
  ) -> Int {
    var starts: [Int] = []
    var next = 0
    for size in sizes {
      starts.append(next)
      next += size
    }

    guard next > 0 else {
      return index
    }

    let bounded = min(max(index, 0), next - 1)

    guard
      let space = sizes.indices.last(where: { starts[$0] <= bounded && sizes[$0] > 0 }),
      let row = rows.firstIndex(where: { $0.contains(space) }),
      let column = rows[row].firstIndex(of: space)
    else {
      return bounded
    }

    let depth = bounded - starts[space]

    switch direction {
    case .left:
      if depth > 0 {
        return bounded - 1
      }

      // Off the front of a row is the end of the row above, not the end of this
      // one: left and right read the whole map in order and meet at its ends, so
      // the arrows never need the other axis to get anywhere.
      let previous =
        column > 0
        ? rows[row][column - 1]
        : rows[(row + rows.count - 1) % rows.count].last ?? space

      return starts[previous] + max(0, sizes[previous] - 1)
    case .right:
      if depth < sizes[space] - 1 {
        return bounded + 1
      }

      let next =
        column + 1 < rows[row].count
        ? rows[row][column + 1]
        : rows[(row + 1) % rows.count].first ?? space

      return starts[next]
    case .up, .down:
      let step = direction == .up ? rows.count - 1 : 1
      let other = rows[(row + step) % rows.count]
      let neighbour = other[min(column, other.count - 1)]

      return starts[neighbour] + min(depth, max(0, sizes[neighbour] - 1))
    }
  }

  /// Where the highlight sits when the overlay opens: on the window you are in.
  ///
  /// The accent fill already says which one that is, so starting the highlight
  /// there makes the two marks agree and gives the arrow keys an obvious origin —
  /// you move away from where you are, rather than from wherever the list happens
  /// to begin.
  /// A Space with nothing on it is the other place you can be standing, and then
  /// there is no window to mark. Opening the overlay from an empty desktop used to
  /// highlight the first tile in the list — some window on another Space — so the
  /// frame said "you are here" and the highlight said somewhere else.
  /// Where you stand comes first, and only then the active window. Standing on an
  /// empty desktop there is still an active window somewhere — the front
  /// application keeps one on the Space you came from, and it can even be a
  /// minimized one — and highlighting that put the mark on another Space entirely.
  static func initialIndex(for targets: [OverlayTarget], standingOn here: WindowSectionID?) -> Int {
    if let here, let index = targets.firstIndex(where: { $0.space == here }) {
      return index
    }

    return targets.firstIndex { $0.window?.isActive == true } ?? 0
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

}
