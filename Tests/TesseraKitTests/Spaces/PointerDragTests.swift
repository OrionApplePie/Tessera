import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("PointerDrag")
struct PointerDragTests {
  /// The path ends where it was aimed. A drop lands where the pointer last was, so
  /// anything short of the target drops the window on whatever is there instead.
  @Test("The path ends at the target")
  func endsAtTheTarget() {
    let path = PointerDrag.steps(
      from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40), count: 20)

    #expect(path.count == 20)
    #expect(path.last == CGPoint(x: 100, y: 40))
  }

  /// The pointer is already at the source, and a move of no distance is what a drag
  /// looks like when the window server ignores it.
  @Test("The path does not start where the pointer already is")
  func skipsTheSource() {
    let source = CGPoint(x: 10, y: 10)
    let path = PointerDrag.steps(from: source, to: CGPoint(x: 50, y: 10), count: 4)

    #expect(path.first != source)
    #expect(
      path == [
        CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 40, y: 10),
        CGPoint(x: 50, y: 10),
      ])
  }

  @Test("A path of no steps is still a landing")
  func alwaysLands() {
    let target = CGPoint(x: 7, y: 9)

    #expect(PointerDrag.steps(from: .zero, to: target, count: 0) == [target])
  }
}
