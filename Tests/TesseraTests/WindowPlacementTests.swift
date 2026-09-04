import CoreGraphics
import Testing

@testable import Tessera

@Suite("WindowPlacement")
struct WindowPlacementTests {
  /// A screen with an odd width, because that is where a doubled half leaves a
  /// seam: the two halves have to meet exactly, whatever the rounding does.
  private let bounds = CGRect(x: 100, y: 50, width: 1001, height: 601)

  @Test("The halves meet exactly and cover the screen between them")
  func halvesMeetInTheMiddle() {
    let left = WindowPlacement.leftHalf.frame(in: bounds)
    let right = WindowPlacement.rightHalf.frame(in: bounds)

    #expect(left.maxX == right.minX)
    #expect(left.minX == bounds.minX)
    #expect(right.maxX == bounds.maxX)
    #expect(left.height == bounds.height)
    #expect(right.height == bounds.height)
  }

  /// Windows are placed from the top left, so the top half is the one nearer the
  /// origin — the opposite of what AppKit's own coordinates would say.
  @Test("The top half is the one at the top of the screen")
  func topHalfIsAtTheTop() {
    let top = WindowPlacement.topHalf.frame(in: bounds)
    let bottom = WindowPlacement.bottomHalf.frame(in: bounds)

    #expect(top.minY == bounds.minY)
    #expect(top.maxY == bottom.minY)
    #expect(bottom.maxY == bounds.maxY)
    #expect(top.width == bounds.width)
  }

  @Test("Filling the screen is the screen")
  func fullIsTheWholeScreen() {
    #expect(WindowPlacement.full.frame(in: bounds) == bounds)
  }

  /// The arrow means the same thing here as everywhere else on the map: that side.
  @Test("An arrow asks for the half it points at")
  func arrowsAskForTheirSide() {
    #expect(WindowPlacement.inDirection(.left) == .leftHalf)
    #expect(WindowPlacement.inDirection(.right) == .rightHalf)
    #expect(WindowPlacement.inDirection(.up) == .topHalf)
    #expect(WindowPlacement.inDirection(.down) == .bottomHalf)
  }
}
