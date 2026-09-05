import CoreGraphics
import Foundation

/// Dragging something with the pointer, the way a hand does it.
///
/// Mission Control moves a window to another Space when its thumbnail is dragged
/// onto that Space in the bar, and there is no other way to ask for it — so the
/// gesture is performed rather than described. The window server wants a gesture,
/// not a jump: a press and a release at two points, with nothing in between, moves
/// nothing, and neither does a single leap from one to the other.
///
/// The pointer really moves while this happens. It is put back afterwards, because
/// the drag is how the work gets done and not a place anybody asked to go.
enum PointerDrag {
  /// How many moves the pointer makes on its way, and how long each one takes.
  /// Fewer or faster than this and the drop lands on nothing.
  private static let stepCount = 20
  private static let stepPause = Duration.milliseconds(12)

  /// How long the button is held before the pointer sets off, and after it arrives
  /// before the button is let go. Both are thresholds rather than tuned delays:
  /// without the first the press is not seen as the start of a drag, without the
  /// second the drop lands while the window is still in flight.
  private static let holdBeforeMoving = Duration.milliseconds(120)
  private static let holdBeforeDropping = Duration.milliseconds(180)

  /// Drags from one point to another, and puts the pointer back where it was.
  static func drag(from source: CGPoint, to target: CGPoint) async {
    let wasAt = CGEvent(source: nil)?.location

    post(.mouseMoved, at: source)
    try? await Task.sleep(for: stepPause)
    post(.leftMouseDown, at: source)
    try? await Task.sleep(for: holdBeforeMoving)

    for point in steps(from: source, to: target, count: stepCount) {
      post(.leftMouseDragged, at: point)
      try? await Task.sleep(for: stepPause)
    }

    try? await Task.sleep(for: holdBeforeDropping)
    post(.leftMouseUp, at: target)

    guard let wasAt else {
      return
    }

    post(.mouseMoved, at: wasAt)
  }

  /// The points the pointer visits on its way, ending at the target.
  ///
  /// The source is not among them: the pointer is already there, and repeating it
  /// would be a move of no distance, which is what a drag looks like when it is
  /// ignored.
  static func steps(from source: CGPoint, to target: CGPoint, count: Int) -> [CGPoint] {
    guard count > 0 else {
      return [target]
    }

    return (1...count).map { step in
      let part = CGFloat(step) / CGFloat(count)

      return CGPoint(
        x: source.x + (target.x - source.x) * part,
        y: source.y + (target.y - source.y) * part
      )
    }
  }

  private static func post(_ type: CGEventType, at point: CGPoint) {
    CGEvent(
      mouseEventSource: nil,
      mouseType: type,
      mouseCursorPosition: point,
      mouseButton: .left
    )?
    .post(tap: .cghidEventTap)
  }
}
