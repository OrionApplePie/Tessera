import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("MissionControl")
@MainActor
struct MissionControlTests {
  /// The point of counting rather than trusting the press: `AXPress` succeeds for a
  /// press that was delivered, which is not the same as a desktop appearing. A
  /// count that did not move means it did not happen.
  @Test("A press that changed nothing did not happen")
  func refusesAnUnchangedCount() {
    #expect(MissionControl.happened(.more, before: 3, after: 3) == false)
    #expect(MissionControl.happened(.fewer, before: 3, after: 3) == false)
  }

  @Test("A desktop that appeared counts as added")
  func acceptsAGrownCount() {
    #expect(MissionControl.happened(.more, before: 3, after: 4))
    #expect(MissionControl.happened(.more, before: 0, after: 1))
  }

  @Test("A Space that went counts as closed")
  func acceptsAShrunkCount() {
    #expect(MissionControl.happened(.fewer, before: 3, after: 2))
  }

  /// A count moving the wrong way is not success either: closing a Space while
  /// something else adds one would otherwise read as done.
  @Test("A count moving the wrong way is not success")
  func refusesTheWrongDirection() {
    #expect(MissionControl.happened(.more, before: 4, after: 3) == false)
    #expect(MissionControl.happened(.fewer, before: 3, after: 4) == false)
  }
}

@Suite("MissionControlTree")
struct MissionControlTreeTests {
  private let displays: [CGDirectDisplayID: CGRect] = [
    1: CGRect(x: 0, y: 0, width: 1512, height: 982),
    2: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
  ]

  /// Which display a Spaces bar belongs to is decided by where it is drawn, because
  /// the order the Dock lists its bars in is the Dock's business and the rest of the
  /// switcher works in display ids.
  @Test("A bar belongs to the display it is drawn on")
  func findsTheDisplayUnderABar() {
    let onTheSecond = CGRect(x: 1712, y: 20, width: 800, height: 90)

    #expect(MissionControlTree.display(forBarAt: onTheSecond, among: displays) == 2)
  }

  @Test("A bar on the main display belongs to it")
  func findsTheMainDisplay() {
    let onTheFirst = CGRect(x: 300, y: 20, width: 700, height: 90)

    #expect(MissionControlTree.display(forBarAt: onTheFirst, among: displays) == 1)
  }

  /// A display that was unplugged between the read and the look leaves a bar
  /// belonging to nowhere, and saying so is better than picking a display at random.
  @Test("A bar on no display belongs to nothing")
  func refusesToGuess() {
    let nowhere = CGRect(x: -4000, y: -4000, width: 800, height: 90)

    #expect(MissionControlTree.display(forBarAt: nowhere, among: displays) == nil)
    #expect(MissionControlTree.display(forBarAt: nowhere, among: [:]) == nil)
  }

  /// The middle decides, not the corner: a bar is centred on its display and a
  /// mirrored or overlapping arrangement would otherwise send it to a neighbour.
  @Test("The middle of the bar decides, not its edge")
  func usesTheMiddleOfTheBar() {
    let straddling = CGRect(x: 1400, y: 20, width: 400, height: 90)

    #expect(MissionControlTree.display(forBarAt: straddling, among: displays) == 2)
  }
}
