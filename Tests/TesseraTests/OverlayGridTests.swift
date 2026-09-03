import CoreGraphics
import Testing

@testable import Tessera

@Suite("OverlayGrid")
struct OverlayGridTests {
  @Test("A row holds up to six tiles and never fewer than one")
  func columnCountIsCappedAtSix() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [], maximum: 6) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [0], maximum: 6) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [3], maximum: 6) == 3)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: 6) == 6)
  }

  @Test("The configured maximum caps the row, and one is the floor")
  func maximumCapsTheRow() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: 4) == 4)
    #expect(OverlayGrid.columnCount(forSectionSizes: [3], maximum: 4) == 3)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: 0) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: -2) == 1)
  }

  /// The map's cell is a Space, and a row is a band of one display: measured on a
  /// machine whose built-in screen holds six Spaces and whose external holds three.
  @Test("A row is a band of one display, up to the row length")
  func spacesAreBandedByDisplay() {
    let displays: [CGDirectDisplayID] = [1, 1, 1, 1, 1, 1, 2, 2, 2]

    #expect(
      OverlayGrid.spaceRows(ofDisplays: displays, perRow: 5) == [
        [0, 1, 2, 3, 4], [5], [6, 7, 8],
      ]
    )
  }

  @Test("A display never shares a row with another one")
  func displaysKeepTheirOwnRows() {
    #expect(OverlayGrid.spaceRows(ofDisplays: [1, 2], perRow: 5) == [[0], [1]])
    #expect(OverlayGrid.spaceRows(ofDisplays: [], perRow: 5).isEmpty)
    #expect(OverlayGrid.spaceRows(ofDisplays: [1, 1], perRow: 0) == [[0], [1]])
  }

  @Test("Every section shares the widest section's column count")
  func columnCountIsSharedAcrossSections() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 5], maximum: 6) == 5)
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 9], maximum: 6) == 6)
  }

  @Test("A screen fits as many tiles across as there is room for")
  func countsTheColumnsAScreenFits() {
    // 190pt tiles, 14pt apart, inside 28pt of surface on each side.
    #expect(TileMetrics.columnsFitting(availableWidth: 1512) == 7)
    #expect(TileMetrics.columnsFitting(availableWidth: 2560) == 12)
    #expect(TileMetrics.columnsFitting(availableWidth: 860) == 4)
  }

  @Test("A screen too narrow for one tile still gets one")
  func neverFitsFewerThanOneColumn() {
    #expect(TileMetrics.columnsFitting(availableWidth: 100) == 1)
    #expect(TileMetrics.columnsFitting(availableWidth: 0) == 1)
  }

  @Test("The highlight starts on the window you are in")
  func initialIndexIsTheActiveWindow() {
    let targets = [makeTile(id: 1), makeTile(id: 2, isActive: true), makeTile(id: 3)]
      .map(OverlayTarget.window)

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 1)
  }

  @Test("With no window frontmost the highlight falls back to the first tile")
  func initialIndexFallsBackToZero() {
    let targets = [makeTile(id: 1), makeTile(id: 2)].map(OverlayTarget.window)

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 0)
    #expect(OverlayGrid.initialIndex(for: [], standingOn: nil) == 0)
  }

  /// While you are in a window there is no Space to stand on: the Space you are in
  /// holds that window, so it is drawn as tiles and never as a place of its own.
  @Test("In a window, the highlight starts on the window")
  func initialIndexPrefersTheActiveWindow() {
    let elsewhere = WindowSectionID(displayID: 1, spaceIndex: 2)
    let targets: [OverlayTarget] = [
      .space(elsewhere), .window(makeTile(id: 1, isActive: true)),
    ]

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 1)
  }

  /// Standing on an empty desktop there is still an active window somewhere — the
  /// front application keeps one on the Space you came from, and it can even be
  /// minimized. Marking that one put "you are here" on another Space.
  @Test("Standing on an empty Space beats an active window somewhere else")
  func initialIndexBeatsAnActiveWindowElsewhere() {
    let here = WindowSectionID(displayID: 1, spaceIndex: 2)
    let targets: [OverlayTarget] = [
      .window(makeTile(id: 1, isActive: true)), .space(here),
    ]

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: here) == 1)
  }

  /// This test used to assert the opposite, on the grounds that you are always in a
  /// window and never in a gap. That stopped being true when an empty desktop
  /// became somewhere you can go: standing on one, there is no window to mark, and
  /// the highlight belongs on the Space you are actually on rather than on the
  /// first tile of the list, which is a window on some other Space.
  @Test("Standing on an empty Space, the highlight starts there")
  func initialIndexIsTheSpaceYouStandOn() {
    let here = WindowSectionID(displayID: 1, spaceIndex: 2)
    let elsewhere = WindowSectionID(displayID: 1, spaceIndex: 3)
    let targets: [OverlayTarget] = [
      .window(makeTile(id: 1)), .space(elsewhere), .space(here),
    ]

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: here) == 2)
    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 0)
  }

  /// One Space of thirteen windows: left and right deal through its deck and wrap
  /// at its ends, because a row of one Space has nowhere else to go.
  @Test("Left and right deal through a Space and wrap")
  func horizontalMovementWalksADeck() {
    let rows = OverlayGrid.spaceRows(ofDisplays: [1], perRow: 5)

    #expect(OverlayGrid.index(from: 0, moving: .right, sizes: [13], rows: rows) == 1)
    #expect(OverlayGrid.index(from: 7, moving: .left, sizes: [13], rows: rows) == 6)
    #expect(OverlayGrid.index(from: 12, moving: .right, sizes: [13], rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, sizes: [13], rows: rows) == 12)
  }

  /// Past the last card of a Space is the Space beside it, and coming back the
  /// other way lands on that neighbour's last card rather than its first.
  @Test("Left and right step to the Space beside this one")
  func horizontalMovementStepsBetweenSpaces() {
    let sizes = [3, 2]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1], perRow: 5)

    #expect(OverlayGrid.index(from: 2, moving: .right, sizes: sizes, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .left, sizes: sizes, rows: rows) == 2)
  }

  /// The end of a row is the start of the next one, and the end of the last row is
  /// the start of the first: right and left walk the whole map and close the loop.
  /// Confined to its own row, right stopped at the edge of a band and only down
  /// carried on, which is not what an arrow that has always wrapped should do.
  @Test("Right off the end of a row lands at the start of the next one")
  func horizontalMovementCrossesRows() {
    let sizes = [2, 2, 2]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1, 2], perRow: 2)

    #expect(rows == [[0, 1], [2]])
    #expect(OverlayGrid.index(from: 3, moving: .right, sizes: sizes, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .left, sizes: sizes, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 5, moving: .right, sizes: sizes, rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, sizes: sizes, rows: rows) == 5)
  }

  /// Up and down are the other axis of the map: the Space above or below, in the
  /// same column, at the same depth in its deck.
  @Test("Up and down move to the Space above or below")
  func verticalMovementMovesBetweenBands() {
    let sizes = [3, 3, 3, 3]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1, 2, 2], perRow: 5)

    #expect(rows == [[0, 1], [2, 3]])
    #expect(OverlayGrid.index(from: 1, moving: .down, sizes: sizes, rows: rows) == 7)
    #expect(OverlayGrid.index(from: 7, moving: .up, sizes: sizes, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 4, moving: .down, sizes: sizes, rows: rows) == 10)
  }

  /// A band with fewer Spaces has no column to match, so the highlight lands in its
  /// last one; a shallower deck has no card at that depth, so it lands on its last.
  @Test("A shorter band and a shallower deck both keep the highlight inside")
  func verticalMovementClampsToWhatIsThere() {
    let sizes = [2, 2, 1]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1, 2], perRow: 5)

    #expect(OverlayGrid.index(from: 3, moving: .down, sizes: sizes, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .up, sizes: sizes, rows: rows) == 0)
  }

  /// This used to stop at the edges. Held down, that reads as an overlay which has
  /// stopped responding — which is how it was reported — and it disagreed with left
  /// and right, which have always wrapped.
  @Test("The top and bottom bands wrap into each other, so an arrow never dead-ends")
  func verticalMovementWrapsAtTheEdges() {
    let sizes = [3, 3]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 2], perRow: 5)

    #expect(OverlayGrid.index(from: 0, moving: .up, sizes: sizes, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .down, sizes: sizes, rows: rows) == 0)
  }

  @Test("A single band wraps onto itself rather than refusing to move")
  func verticalMovementInOneBand() {
    let rows = OverlayGrid.spaceRows(ofDisplays: [1], perRow: 5)

    #expect(OverlayGrid.index(from: 1, moving: .down, sizes: [3], rows: rows) == 1)
    #expect(OverlayGrid.index(from: 1, moving: .up, sizes: [3], rows: rows) == 1)
  }

  @Test("An out-of-range starting index is brought back in bounds")
  func clampsAnOutOfRangeIndex() {
    let rows = OverlayGrid.spaceRows(ofDisplays: [1], perRow: 5)

    #expect(OverlayGrid.index(from: 99, moving: .right, sizes: [3], rows: rows) == 0)
    #expect(OverlayGrid.index(from: -4, moving: .right, sizes: [3], rows: rows) == 1)
  }

  @Test("With no tiles every direction is a no-op")
  func emptyGridDoesNotMove() {
    for direction in [OverlayGrid.Direction.left, .right, .up, .down] {
      #expect(OverlayGrid.index(from: 0, moving: direction, sizes: [], rows: []) == 0)
    }
  }

  @Test("A letter jumps to the window of that name")
  func jumpsToTheMatchingApplication() {
    let tiles = [
      makeTile(id: 1, appName: "Arc"),
      makeTile(id: 2, appName: "Code"),
      makeTile(id: 3, appName: "Safari"),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "c", in: tiles, field: .applicationName) == 1)
    #expect(OverlayGrid.index(from: 0, matching: "s", in: tiles, field: .applicationName) == 2)
  }

  @Test("The same letter again moves on to the next window of that name")
  func repeatedLetterCycles() {
    let tiles = [
      makeTile(id: 1, appName: "Claude"),
      makeTile(id: 2, appName: "Code"),
      makeTile(id: 3, appName: "Safari"),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "c", in: tiles, field: .applicationName) == 1)
    #expect(OverlayGrid.index(from: 1, matching: "c", in: tiles, field: .applicationName) == 0)
  }

  @Test("Case does not matter, in the key or in the name")
  func matchingIgnoresCase() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "code")]

    #expect(OverlayGrid.index(from: 0, matching: "C", in: tiles, field: .applicationName) == 1)
  }

  @Test("The only window of that name keeps the highlight where it is")
  func aSingleMatchStaysPut() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    #expect(OverlayGrid.index(from: 1, matching: "c", in: tiles, field: .applicationName) == 1)
  }

  @Test("A letter nothing starts with matches nothing at all")
  func noMatchIsReportedAsSuch() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    // Not the current index: the caller has to tell "no window of that name" from
    // "the only one is already here", so that another reading of the key can run.
    #expect(OverlayGrid.index(from: 1, matching: "z", in: tiles, field: .applicationName) == nil)
    #expect(
      OverlayGrid.index(
        from: 0, matching: "z", in: [] as [WindowTileModel], field: .applicationName) == nil)
  }

  @Test("A letter can be matched against the window titles instead")
  func matchesAgainstTheWindowTitle() {
    let tiles = [
      makeTile(id: 1, appName: "Finder", title: "Downloads"),
      makeTile(id: 2, appName: "Finder", title: "Тезисы"),
      makeTile(id: 3, appName: "Finder", title: "Documents"),
    ]

    // The search still starts after the current tile.
    #expect(OverlayGrid.index(from: 0, matching: "d", in: tiles, field: .windowTitle) == 2)
    #expect(OverlayGrid.index(from: 2, matching: "d", in: tiles, field: .windowTitle) == 0)
    #expect(OverlayGrid.index(from: 0, matching: "т", in: tiles, field: .windowTitle) == 1)
  }

  @Test("The two fields are searched separately, so a caller can rank them")
  func fieldsAreSearchedSeparately() {
    let tiles = [
      makeTile(id: 1, appName: "Finder", title: "Code review"),
      makeTile(id: 2, appName: "Code", title: "Something"),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "c", in: tiles, field: .applicationName) == 1)
    #expect(OverlayGrid.index(from: 1, matching: "c", in: tiles, field: .windowTitle) == 0)
  }

  @Test("An out-of-range index does not stop a jump")
  func jumpClampsTheStartingIndex() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    #expect(OverlayGrid.index(from: 99, matching: "a", in: tiles, field: .applicationName) == 0)
  }

  private func makeTile(
    id: CGWindowID,
    isActive: Bool = false,
    appName: String = "Finder",
    title: String = "Downloads"
  ) -> WindowTileModel {
    WindowTileModel(
      id: id,
      appName: appName,
      title: title,
      processID: 100,
      isActive: isActive,
      isMinimized: false,
      displayID: 1,
      spaceIndex: nil,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )
  }
}

@Suite("OverlayGrid placement")
struct OverlayGridPlacementTests {
  /// The second display in the layout this was measured on sits above and to the
  /// left of the built-in one, so its usable area starts at a negative x and a
  /// positive y. Centring that forgot the origin would land the panel on the
  /// built-in screen instead.
  private static let external = CGRect(x: -485, y: 982, width: 2560, height: 1415)

  @Test("A panel is centred in the usable area of the screen it opens on")
  func centresOnTheScreenGiven() throws {
    let placed = try #require(
      OverlayGrid.placement(for: CGSize(width: 858, height: 1312), in: Self.external))

    #expect(placed.midX == Self.external.midX)
    #expect(placed.midY == Self.external.midY)
    #expect(placed.size == CGSize(width: 858, height: 1312))
  }

  @Test("A panel wider than the screen is still centred, not pushed to the edge")
  func centresEvenWhenOversized() throws {
    let usable = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let placed = try #require(
      OverlayGrid.placement(for: CGSize(width: 1600, height: 400), in: usable))

    #expect(placed.minX == -44)
    #expect(placed.midX == usable.midX)
  }

  @Test("An unknown screen places nothing, leaving the fallback to the caller")
  func reportsNothingForAnUnknownScreen() {
    #expect(OverlayGrid.placement(for: CGSize(width: 100, height: 100), in: .zero) == nil)
  }

  @Test("A panel with no size places nothing")
  func reportsNothingForAnEmptySize() {
    #expect(OverlayGrid.placement(for: .zero, in: Self.external) == nil)
  }
}
