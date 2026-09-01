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

  @Test("A narrower maximum wraps a section sooner")
  func maximumWrapsSectionsSooner() {
    #expect(
      OverlayGrid.rows(forSectionSizes: [5], maximum: 4) == [[0, 1, 2, 3], [4]])
    #expect(
      OverlayGrid.rows(forSectionSizes: [5], maximum: 2) == [[0, 1], [2, 3], [4]])
  }

  @Test("Every section shares the widest section's column count")
  func columnCountIsSharedAcrossSections() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 5], maximum: 6) == 5)
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 9], maximum: 6) == 6)
  }

  @Test("A section always starts a new row")
  func sectionsStartNewRows() {
    #expect(OverlayGrid.rows(forSectionSizes: [3, 2], maximum: 6) == [[0, 1, 2], [3, 4]])
  }

  @Test("A section longer than a row wraps")
  func longSectionsWrap() {
    #expect(
      OverlayGrid.rows(forSectionSizes: [8, 2], maximum: 6) == [
        [0, 1, 2, 3, 4, 5], [6, 7], [8, 9],
      ]
    )
  }

  @Test("Empty sections take up no rows")
  func emptySectionsAreSkipped() {
    #expect(OverlayGrid.rows(forSectionSizes: [0, 2], maximum: 6) == [[0, 1]])
    #expect(OverlayGrid.rows(forSectionSizes: [], maximum: 6).isEmpty)
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
    let tiles = [makeTile(id: 1), makeTile(id: 2, isActive: true), makeTile(id: 3)]

    #expect(OverlayGrid.initialIndex(for: tiles) == 1)
  }

  @Test("With no window frontmost the highlight falls back to the first tile")
  func initialIndexFallsBackToZero() {
    #expect(OverlayGrid.initialIndex(for: [makeTile(id: 1), makeTile(id: 2)]) == 0)
    #expect(OverlayGrid.initialIndex(for: []) == 0)
  }

  @Test("Left and right step through the tiles in reading order and wrap")
  func horizontalMovementWalksTheList() {
    let rows = OverlayGrid.rows(forSectionSizes: [13], maximum: 6)

    #expect(OverlayGrid.index(from: 0, moving: .right, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 7, moving: .left, rows: rows) == 6)
    #expect(OverlayGrid.index(from: 12, moving: .right, rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, rows: rows) == 12)
  }

  @Test("Left and right cross a section boundary without noticing it")
  func horizontalMovementCrossesSections() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 2], maximum: 6)

    #expect(OverlayGrid.index(from: 2, moving: .right, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .left, rows: rows) == 2)
  }

  @Test("Up and down move a whole row")
  func verticalMovementMovesARow() {
    let rows = OverlayGrid.rows(forSectionSizes: [13], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 7)
    #expect(OverlayGrid.index(from: 7, moving: .up, rows: rows) == 1)
  }

  @Test("Down from the last row of a section lands in the next section")
  func verticalMovementEntersTheNextSection() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 3], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .up, rows: rows) == 1)
  }

  @Test("A shorter row keeps the highlight in its last column")
  func verticalMovementClampsToAShorterRow() {
    let rows = OverlayGrid.rows(forSectionSizes: [4, 2], maximum: 6)

    // Column 3 has nothing under it, so the highlight lands on the row's last tile.
    #expect(OverlayGrid.index(from: 3, moving: .down, rows: rows) == 5)
  }

  @Test("Coming back up returns to the column the highlight actually sits in")
  func verticalMovementHasNoColumnMemory() {
    let rows = OverlayGrid.rows(forSectionSizes: [4, 2], maximum: 6)

    // Down from column 3 clamped to column 1, so up goes to column 1, not back to 3.
    #expect(OverlayGrid.index(from: 5, moving: .up, rows: rows) == 1)
  }

  /// This used to stop at the edges. Held down, that reads as an overlay which has
  /// stopped responding — which is how it was reported — and it disagreed with left
  /// and right, which have always wrapped.
  @Test("The top and bottom rows wrap into each other, so an arrow never dead-ends")
  func verticalMovementWrapsAtTheEdges() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 3], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .up, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .down, rows: rows) == 1)
  }

  @Test("A single row wraps onto itself rather than refusing to move")
  func verticalMovementInOneRow() {
    let rows = OverlayGrid.rows(forSectionSizes: [3], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 1, moving: .up, rows: rows) == 1)
  }

  @Test("An out-of-range starting index is brought back in bounds")
  func clampsAnOutOfRangeIndex() {
    let rows = OverlayGrid.rows(forSectionSizes: [3], maximum: 6)

    #expect(OverlayGrid.index(from: 99, moving: .right, rows: rows) == 0)
    #expect(OverlayGrid.index(from: -4, moving: .right, rows: rows) == 1)
  }

  @Test("With no tiles every direction is a no-op")
  func emptyGridDoesNotMove() {
    for direction in [OverlayGrid.Direction.left, .right, .up, .down] {
      #expect(OverlayGrid.index(from: 0, moving: direction, rows: []) == 0)
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
