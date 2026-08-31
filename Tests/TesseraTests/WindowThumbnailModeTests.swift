import CoreGraphics
import Testing

@testable import Tessera

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
}
