import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("DisplayInfo")
struct DisplayInfoTests {
  /// Roughly the layout this was developed on: a built-in display at the origin
  /// and a larger one placed above and to the left, so its coordinates are negative.
  private let builtIn = DisplayInfo(
    id: 1,
    name: "Color LCD",
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982)
  )
  private let external = DisplayInfo(
    id: 2,
    name: "VG27AQL1A",
    frame: CGRect(x: -485, y: -1440, width: 2560, height: 1440)
  )

  @Test("A window sitting inside one display belongs to it")
  func resolvesAContainedWindow() {
    let window = CGRect(x: 10, y: 56, width: 1492, height: 867)

    #expect(DisplayInfo.display(for: window, among: [builtIn, external])?.id == 1)
  }

  @Test("Negative coordinates resolve to the display above and to the left")
  func resolvesANegativelyPositionedWindow() {
    let window = CGRect(x: -485, y: -1415, width: 2560, height: 1415)

    #expect(DisplayInfo.display(for: window, among: [builtIn, external])?.id == 2)
  }

  @Test("A window straddling two displays belongs to the one covering more of it")
  func picksTheLargerOverlap() {
    // 100pt tall, 80 of them below y = 0 and so on the built-in display.
    let window = CGRect(x: 100, y: -20, width: 200, height: 100)

    #expect(DisplayInfo.display(for: window, among: [builtIn, external])?.id == 1)

    // The same window nudged up: now most of it is on the external display.
    let higher = CGRect(x: 100, y: -80, width: 200, height: 100)

    #expect(DisplayInfo.display(for: higher, among: [builtIn, external])?.id == 2)
  }

  @Test("A window that touches no display resolves to nothing")
  func returnsNothingForAWindowOffTheCanvas() {
    let window = CGRect(x: 9000, y: 9000, width: 100, height: 100)

    #expect(DisplayInfo.display(for: window, among: [builtIn, external]) == nil)
    #expect(DisplayInfo.display(for: window, among: []) == nil)
  }

  @Test("An edge that merely touches a display is not an overlap")
  func zeroAreaOverlapDoesNotCount() {
    // Sits on the external display, with its right edge flush against the built-in
    // display's left edge. Touching is not covering.
    let window = CGRect(x: -200, y: -200, width: 200, height: 100)

    #expect(DisplayInfo.display(for: window, among: [builtIn, external])?.id == 2)
  }

  @Test("A window in the gap between displays belongs to neither")
  func aWindowInTheGapResolvesToNothing() {
    // Left of the built-in display and below the external one: inside the bounding
    // box of the two, but on neither.
    let window = CGRect(x: -200, y: 0, width: 200, height: 100)

    #expect(DisplayInfo.display(for: window, among: [builtIn, external]) == nil)
  }

  @Test("A display standing above another comes first")
  func higherDisplayComesFirst() {
    // The external display sits entirely above the built-in one.
    #expect(DisplayInfo.order(of: [builtIn, external]) == [2, 1])
  }

  @Test("Which display is main does not change the order")
  func mainDisplayDoesNotChangeTheOrder() {
    // Nothing here says which display holds the menu bar, and nothing should.
    #expect(DisplayInfo.order(of: [external, builtIn]) == [2, 1])
  }

  @Test("Displays side by side are ordered left to right")
  func sideBySideDisplaysGoLeftToRight() {
    let left = DisplayInfo(
      id: 3, name: "Left", frame: CGRect(x: -1512, y: 0, width: 1512, height: 982))
    let right = DisplayInfo(
      id: 4, name: "Right", frame: CGRect(x: 1512, y: 0, width: 1512, height: 982))

    #expect(DisplayInfo.order(of: [right, builtIn, left]) == [3, 1, 4])
  }

  @Test("A small vertical offset does not break a row apart")
  func slightlyOffsetDisplaysStayInOneRow() {
    // Two screens side by side, one nudged 100pt up: still one row, left first.
    let nudged = DisplayInfo(
      id: 5, name: "Nudged", frame: CGRect(x: 1512, y: -100, width: 1512, height: 982))

    #expect(DisplayInfo.order(of: [nudged, builtIn]) == [1, 5])
  }

  @Test("Rows are ordered top to bottom, and each row left to right")
  func rowsAreOrderedTopToBottomThenLeftToRight() {
    let topLeft = DisplayInfo(
      id: 6, name: "Top left", frame: CGRect(x: -2000, y: -1000, width: 1000, height: 800))
    let topRight = DisplayInfo(
      id: 7, name: "Top right", frame: CGRect(x: 0, y: -1000, width: 1000, height: 800))

    #expect(DisplayInfo.order(of: [builtIn, topRight, topLeft]) == [6, 7, 1])
  }

  @Test("A single display needs no ordering")
  func singleDisplayOrder() {
    #expect(DisplayInfo.order(of: [builtIn]) == [1])
    #expect(DisplayInfo.order(of: []).isEmpty)
  }

  @Test("The order does not depend on the order displays arrive in")
  func orderIsStable() {
    let forwards = DisplayInfo.order(of: [builtIn, external])
    let backwards = DisplayInfo.order(of: [external, builtIn])

    #expect(forwards == backwards)
  }

  /// macOS calls the laptop's own screen "Built-in Retina Display" — three words to
  /// say what one says, and twice the width of an external display's name next to
  /// it on the map.
  @Test("A display name keeps only what tells it apart")
  func shortensDisplayNames() {
    #expect(DisplayInfo.shortened("Built-in Retina Display") == "Built-in")
    #expect(DisplayInfo.shortened("LG UltraFine Display") == "LG UltraFine")
    #expect(DisplayInfo.shortened("VQ27AQL1A") == "VQ27AQL1A")
  }

  /// A name made of nothing but those words is left alone: something has to be
  /// drawn, and the original says more than an empty heading.
  @Test("A name with nothing left is kept whole")
  func keepsANameWithNothingLeft() {
    #expect(DisplayInfo.shortened("Display") == "Display")
  }
}

/// Where a window lands when it is sent to another screen. The two displays here
/// are a wide one and a half-sized one beside it, which is the pair that makes the
/// difference between copying an offset and keeping a proportion visible.
@Suite("Sending a window to another display")
struct DisplayInfoMovingTests {
  private let source = CGRect(x: 0, y: 0, width: 2000, height: 1000)
  private let target = CGRect(x: 2000, y: 0, width: 1000, height: 500)

  @Test("A window that fits arrives the same size")
  func keepsTheSizeWhenItFits() {
    let window = CGRect(x: 0, y: 0, width: 200, height: 100)
    let moved = DisplayInfo.frame(window, movedFrom: source, to: target)

    #expect(moved == CGRect(x: 2000, y: 0, width: 200, height: 100))
  }

  /// The proportion is of the room the window has to move in, not of the screen:
  /// a window against the far edge belongs against the far edge, whatever the two
  /// screens measure.
  @Test("A window against an edge arrives against that edge")
  func keepsAWindowOnItsEdge() {
    let window = CGRect(x: 1800, y: 900, width: 200, height: 100)
    let moved = DisplayInfo.frame(window, movedFrom: source, to: target)

    #expect(moved == CGRect(x: 2800, y: 400, width: 200, height: 100))
  }

  @Test("A window halfway across arrives halfway across")
  func keepsAWindowInTheMiddle() {
    let window = CGRect(x: 900, y: 450, width: 200, height: 100)
    let moved = DisplayInfo.frame(window, movedFrom: source, to: target)

    #expect(moved == CGRect(x: 2400, y: 200, width: 200, height: 100))
  }

  /// Shrunk keeping its shape, and only as far as it has to be: a window sent to a
  /// smaller screen and back should be recognisable, not reshaped.
  @Test("A window too large for the screen is taken down to fit")
  func shrinksAWindowThatDoesNotFit() {
    let window = CGRect(x: 0, y: 0, width: 1500, height: 900)
    let moved = DisplayInfo.frame(window, movedFrom: source, to: target)

    #expect(moved.width == 833)
    #expect(moved.height == 500)
    #expect(target.contains(moved))
  }

  @Test("A display with no size leaves the window alone")
  func leavesTheWindowAloneWithoutADisplay() {
    let window = CGRect(x: 10, y: 20, width: 200, height: 100)

    #expect(DisplayInfo.frame(window, movedFrom: source, to: .zero) == window)
  }
}
