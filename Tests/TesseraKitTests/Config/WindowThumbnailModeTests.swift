import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("WindowThumbnailMode")
struct WindowThumbnailModeTests {
  private static let tile = CGSize(width: 166, height: 100)
  private static let window = CGSize(width: 1512, height: 944)

  @Test("Every mode parses under the name the config documents")
  func parsesDocumentedNames() throws {
    for mode in WindowThumbnailMode.allCases {
      let parsed = try WindowThumbnailMode(parsing: mode.name)
      #expect(parsed == mode)
    }
  }

  @Test("Spelling a mode another way still names the same mode")
  func acceptsAliases() throws {
    #expect(try WindowThumbnailMode(parsing: " WHOLE ") == .fit)
    #expect(try WindowThumbnailMode(parsing: "top-left") == .corner)
    #expect(try WindowThumbnailMode(parsing: "corner-2x") == .cornerDouble)
    #expect(try WindowThumbnailMode(parsing: "fourth") == .quarter)
  }

  @Test("A mode nobody defined is an error, not a silent default")
  func rejectsTheUnknown() {
    #expect(throws: WindowThumbnailModeError.unknown("sideways")) {
      try WindowThumbnailMode(parsing: "sideways")
    }
  }

  @Test("A corner is the tile itself, so it is drawn at its own size")
  func cropsTheTileItself() {
    let crop = WindowThumbnailMode.corner.crop(ofWindow: Self.window, tile: Self.tile)

    #expect(crop == Self.tile)
  }

  @Test("Twice the corner is twice the tile across and down")
  func cropsTwiceTheTile() {
    let crop = WindowThumbnailMode.cornerDouble.crop(ofWindow: Self.window, tile: Self.tile)

    #expect(crop == CGSize(width: Self.tile.width * 2, height: Self.tile.height * 2))
  }

  @Test("A quarter takes a quarter of the window's area")
  func cropsAQuarterOfTheArea() {
    let crop = WindowThumbnailMode.quarter.crop(ofWindow: Self.window, tile: Self.tile)
    let area = crop.width * crop.height

    #expect(abs(area - Self.window.width * Self.window.height / 4) < 1)
  }

  @Test("Every corner keeps the tile's proportions, so nothing is cropped twice")
  func keepsTheTileProportions() {
    let tileRatio = Self.tile.width / Self.tile.height

    for mode in [WindowThumbnailMode.corner, .cornerDouble, .quarter] {
      let crop = mode.crop(ofWindow: Self.window, tile: Self.tile)
      #expect(abs(crop.width / crop.height - tileRatio) < 0.001)
    }
  }

  @Test("A window smaller than the piece asked for is taken whole")
  func takesASmallWindowWhole() {
    let small = CGSize(width: 80, height: 60)

    for mode in [WindowThumbnailMode.corner, .cornerDouble, .quarter] {
      #expect(mode.crop(ofWindow: small, tile: Self.tile) == small)
    }
  }

  @Test("A window with no size still asks for something capturable")
  func neverAsksForNothing() {
    for mode in WindowThumbnailMode.allCases {
      let crop = mode.crop(ofWindow: .zero, tile: Self.tile)
      #expect(crop.width >= 1)
      #expect(crop.height >= 1)
    }
  }

  @Test("Three quarters is read by name and by number")
  func readsThreeQuarters() throws {
    #expect(try WindowThumbnailMode(parsing: "75") == .threeQuarters)
    #expect(try WindowThumbnailMode(parsing: "three-quarters") == .threeQuarters)
    #expect(WindowThumbnailMode.threeQuarters.name == "75")
  }

  /// Three quarters of a window is a larger piece than a quarter of it, so it is
  /// scaled down further to reach the same tile — which is the whole difference
  /// between the two: how much of the window survives, and how small it ends up.
  @Test("Three quarters takes more of the window than a quarter")
  func takesMoreThanAQuarter() {
    let window = CGSize(width: 1600, height: 1000)
    let tile = CGSize(width: 166, height: 120)

    let quarter = WindowThumbnailMode.quarter.crop(ofWindow: window, tile: tile)
    let three = WindowThumbnailMode.threeQuarters.crop(ofWindow: window, tile: tile)

    #expect(three.width > quarter.width)
    #expect(three.height > quarter.height)
    #expect(three.width <= window.width)
  }

  /// A crop keeps the tile's shape, and the tile is square — so a window far from
  /// square loses exactly what identifies it. Measured on the window that prompted
  /// this: 338 by 612 points, three quarters of which is its top third.
  @Test("A tall narrow window counts as long")
  func spotsATallWindow() {
    #expect(WindowThumbnailMode.isLong(CGSize(width: 338, height: 612)))
    #expect(WindowThumbnailMode.isLong(CGSize(width: 2000, height: 600)))
  }

  /// An ordinary window is not: it is close enough to the tile's shape that a piece
  /// of it still says which window it is.
  /// Measured on this desktop: ordinary windows run from 1.40 to 1.60 sides, and
  /// the ones this rule is for start at 1.8.
  @Test("An ordinary window is not long")
  func leavesOrdinaryWindowsAlone() {
    #expect(!WindowThumbnailMode.isLong(CGSize(width: 1512, height: 944)))
    #expect(!WindowThumbnailMode.isLong(CGSize(width: 1200, height: 800)))
    #expect(!WindowThumbnailMode.isLong(CGSize(width: 900, height: 900)))
    #expect(!WindowThumbnailMode.isLong(.zero))
  }

  /// The setting decides, and only for the windows the rule catches: everything
  /// else is captured the way it was asked for.
  @Test("A long window is taken whole only when that is asked for")
  func takesLongWindowsWholeWhenAsked() {
    let long = CGSize(width: 338, height: 612)
    let ordinary = CGSize(width: 1200, height: 800)

    #expect(
      WindowThumbnailMode.capturing(long, wanted: .threeQuarters, takingLongWindowsWhole: true)
        == .fit)
    #expect(
      WindowThumbnailMode.capturing(long, wanted: .threeQuarters, takingLongWindowsWhole: false)
        == .threeQuarters)
    #expect(
      WindowThumbnailMode.capturing(ordinary, wanted: .corner, takingLongWindowsWhole: true)
        == .corner)
  }
}
