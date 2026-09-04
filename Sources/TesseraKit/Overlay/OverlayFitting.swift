import AppKit
import QuartzCore
import SwiftUI

/// Choosing how wide the grid is and how large the panel must be to hold it.
extension OverlayWindowController {

  /// The display the overlay opens on: the one showing the Space the system calls
  /// active.
  ///
  /// Neither of the obvious two answers survives both directions. `NSScreen.main` is
  /// the screen of the window with keyboard focus, and after showing a Space on
  /// another display it still names the display just left — the overlay opened on a
  /// Space nobody was looking at, and which display that was depended on the
  /// application in front, which is why it looked intermittent. The pointer, moved
  /// to the display whose Space was shown, then fails the other way: it stays there
  /// after the attention has gone back to a window elsewhere. The active Space
  /// follows the focus across displays in both cases.
  var screenInFront: NSScreen? {
    windowCoordinator.activeDisplay.flatMap(DisplayInfo.screen(for:)) ?? NSScreen.main
  }

  /// Widens the grid until it is no taller than the screen, or until no more tiles
  /// fit across it.
  ///
  /// The configured column count is where this starts, not what it insists on: a
  /// column count that reads well with six windows leaves sixteen taller than a
  /// laptop screen, and a switcher nobody can see all of is not doing its job.
  /// Measured rather than calculated — SwiftUI's own fitting size is the only
  /// answer that accounts for the headings.
  func fitToScreen(within usable: CGSize) -> CGSize {
    // The list is frozen while the overlay is up, so a screen of the same size asks
    // for the same layout. Measuring it again is not free — it builds the whole
    // view twice over and then replaces the live one — and doing that on every
    // keypress is what made stepping stall after a few crossings.
    if let lastFit, lastFit.usable == usable {
      return lastFit.size
    }

    if config.overlayFillsScreen {
      return fillTheScreen(usable)
    }

    metrics = .base

    let widest = metrics.columnsFitting(availableWidth: usable.width)

    var chosen = config.overlayColumns
    var size = measure(columns: chosen)

    while size.height > usable.height, chosen < widest {
      chosen += 1
      size = measure(columns: chosen)
    }

    fittedColumns = chosen
    hostingView.rootView = makeOverlayView()
    lastFit = (usable, size)
    return size
  }

  /// The overlay grown out of its grid rather than stretched to the screen.
  ///
  /// The screen is the ceiling, not the shape: the tile is taken as large as the
  /// grid allows while the whole map still stands inside the screen less a margin,
  /// and the panel is then exactly as big as that map — no panel edge sitting a
  /// long way from the last tile, and no row falling off the bottom. A margin is
  /// left because a panel flush to the edges reads as a mode the Mac has entered
  /// rather than as something drawn over what is already there.
  private func fillTheScreen(_ usable: CGSize) -> CGSize {
    let margin = max(24, min(usable.width, usable.height) * 0.04).rounded()
    let room = CGSize(width: usable.width - margin * 2, height: usable.height - margin * 2)
    let size = growIntoTheRoom(room)

    hostingView.rootView = makeOverlayView()
    hostingView.layer?.cornerRadius = metrics.surfaceCornerRadius
    lastFit = (usable, size)

    return size
  }

  /// The largest tile the room can carry, and — unless the config has already said
  /// — how many Spaces go across.
  ///
  /// Wider rows mean smaller tiles and fewer rows; narrower rows mean larger tiles
  /// and more of them. Which way round wins depends on how many Spaces there are
  /// and how tall the screen is, so it is measured rather than assumed: every row
  /// length is grown into the room and the largest tile among those that fit wins.
  /// A fixed row length is the same walk with one candidate — the count is settled,
  /// the size still is not.
  @discardableResult
  private func growIntoTheRoom(_ room: CGSize) -> CGSize {
    // The configured count belongs to the fixed layout alone. Used as a ceiling on
    // the others it cost a row — six Spaces that fit across in one went to three and
    // three — and a layout free to choose should not be told to leave room. The
    // settings window says as much rather than leaving the number looking ignored.
    let spaces = max(1, windowCoordinator.sections.count)
    let candidates: [Int]

    switch config.overlayLayout {
    case .rows:
      candidates = [max(1, config.overlayColumns)]
    case .count:
      candidates = [min(OverlayGrid.columns(forCount: spaces), 12)]
    case .fitted, .flow:
      candidates = Array(1...min(spaces, 12))
    }

    var best: FittedMap?

    for candidate in candidates {
      fittedColumns = candidate
      metrics = TileMetrics.filling(
        width: room.width, columns: widestRow(under: candidate), style: config.overlayDeck)

      let size = shrinkToFit(room)

      guard size.height <= room.height, size.width <= room.width else {
        continue
      }

      if metrics.width > (best?.metrics.width ?? 0) {
        best = FittedMap(columns: candidate, metrics: metrics, size: size)
      }
    }

    guard let best else {
      // Nothing fits: the smallest tile on the longest row is the least bad, and
      // the panel says so by overflowing rather than by hiding a row.
      fittedColumns = candidates[candidates.count - 1]
      metrics = TileMetrics(width: tileFloor)

      return measure(columns: fittedColumns)
    }

    fittedColumns = best.columns
    metrics = best.metrics

    return best.size
  }

  /// A row length that fits, with the tile it fits at and the room it takes.
  private struct FittedMap {
    let columns: Int
    let metrics: TileMetrics
    let size: CGSize
  }

  /// How many cells the longest row actually holds under a given limit.
  ///
  /// Not the same as the limit: bands are split evenly and a display may hold fewer
  /// Spaces than a row allows, so a map of four and three under a limit of five was
  /// sized for five and sat in four fifths of the panel. The tile is solved for the
  /// row that is really there.
  private func widestRow(under limit: Int) -> Int {
    let rows = OverlayGrid.spaceRows(
      ofDisplays: windowCoordinator.sections.map(\.id.displayID),
      perRow: limit,
      banded: config.overlayLayout.isBanded
    )

    return max(1, rows.map(\.count).max() ?? limit)
  }

  /// The smallest a tile is allowed to be here: what the configuration asks for,
  /// but never below what the tile itself can be drawn at.
  private var tileFloor: CGFloat {
    max(TileMetrics.range.lowerBound, config.overlayMinTile)
  }

  /// Takes the tile down until the map fits the room, and says how big the map
  /// ended up.
  ///
  /// Solving for the width cannot know how many rows the Spaces will make, and the
  /// heading above each of them is not a fraction of anything — so the height is
  /// measured and the tile shrunk by whatever it overflowed by. The step is forced
  /// to be a step: a tile that rounds back to the width it already had would loop,
  /// and two passes at a fixed count of them was what left the bottom row off the
  /// screen.
  private func shrinkToFit(_ room: CGSize) -> CGSize {
    var size = measure(columns: fittedColumns)
    var passes = 0

    while metrics.width > tileFloor, passes < 8 {
      // Both directions, because the tile solved for the width lands a rounded
      // point over it as often as under: a map judged not to fit by one point was
      // dropped for the smallest tile in the range, and the whole screen-filling
      // layout collapsed to a postage stamp.
      let ratio = min(room.height / size.height, room.width / size.width)

      guard ratio < 1 else {
        break
      }

      metrics = TileMetrics(width: min((metrics.width * ratio).rounded(), metrics.width - 1))
      size = measure(columns: fittedColumns)
      passes += 1
    }

    return size
  }

  /// Measured on a throwaway view rather than on the one on screen: an
  /// `NSHostingView` does not re-report its fitting size synchronously when its
  /// root view is replaced, so asking the live view in a loop returns the first
  /// answer every time — which is how the first version of this widened the grid
  /// to the edge of the screen and then sized the window for the layout it had
  /// rejected.
  private func measure(columns count: Int) -> CGSize {
    TransparentHostingView(rootView: makeOverlayView(columns: count)).fittingSize
  }

  func makeOverlayView(columns count: Int? = nil) -> OverlayView {
    OverlayView(
      metrics: metrics,
      windowCoordinator: windowCoordinator,
      selection: selection,
      background: config.overlayBackground,
      columns: count ?? fittedColumns,
      deck: config.overlayDeck,
      arrangement: config.overlayLayout,
      search: config.overlaySearch,
      rowAlignment: config.overlayRowAlignment,
      dimsStaleThumbnails: config.dimsStaleThumbnails,
      onSelect: { [weak self] windowID in
        self?.selectWindow(id: windowID)
      },
      onFocusSpace: { [weak self] section in
        self?.focusSpace(section)
      },
      onMove: { [weak self] windowID, targetID in
        self?.moveOrSend(windowID, onto: targetID)
      },
      onClose: { [weak self] in
        self?.hideOverlay()
      }
    )
  }
}

/// A hosting view that does not paint over the shape its content draws.
///
/// `NSHostingView` fills its own bounds with an opaque background, which squares
/// off the rounded corners the overlay draws for itself — measured as a single
/// anti-aliased pixel at the corner of an otherwise solid rectangle. No property
/// turns that off, so the view declares itself transparent instead.
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool {
    false
  }

  required init(rootView: Content) {
    super.init(rootView: rootView)

    wantsLayer = true
    layer?.backgroundColor = .clear
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
