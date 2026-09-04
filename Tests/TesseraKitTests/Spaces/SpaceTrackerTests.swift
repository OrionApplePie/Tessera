import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("SpaceTracker")
struct SpaceTrackerTests {
  @Test("The first windows seen together become the first Space")
  func firstObservationCreatesASpace() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2], on: 1)

    #expect(tracker.spaceIndex(of: 1, on: 1) == 0)
    #expect(tracker.spaceIndex(of: 2, on: 1) == 0)
    #expect(tracker.knownSpaceCount(on: 1) == 1)
  }

  @Test("A window nobody has seen on screen has no Space")
  func unseenWindowsHaveNoSpace() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1], on: 1)

    #expect(tracker.spaceIndex(of: 99, on: 1) == nil)
    #expect(tracker.spaceIndex(of: 1, on: 2) == nil)
  }

  @Test("A completely different set of windows is a different Space")
  func disjointObservationCreatesASecondSpace() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2], on: 1)
    tracker.observe(onScreen: [3, 4], on: 1)

    #expect(tracker.spaceIndex(of: 1, on: 1) == 0)
    #expect(tracker.spaceIndex(of: 3, on: 1) == 1)
    #expect(tracker.knownSpaceCount(on: 1) == 2)
  }

  @Test("Coming back to a Space updates it instead of inventing another")
  func overlappingObservationUpdatesTheSameSpace() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2], on: 1)
    tracker.observe(onScreen: [3], on: 1)
    // Back on the first Space, where a new window has since opened.
    tracker.observe(onScreen: [1, 2, 5], on: 1)

    #expect(tracker.knownSpaceCount(on: 1) == 2)
    #expect(tracker.spaceIndex(of: 5, on: 1) == 0)
  }

  @Test("A window that has left a Space stops being counted in it")
  func aWindowThatLeftIsForgottenByItsOldSpace() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2], on: 1)
    // Window 2 is gone from that Space now.
    tracker.observe(onScreen: [1], on: 1)

    #expect(tracker.spaceIndex(of: 2, on: 1) == nil)
  }

  @Test("A window moved to another Space follows it")
  func aWindowMovedBetweenSpacesFollows() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2], on: 1)
    tracker.observe(onScreen: [3, 4], on: 1)
    // Window 1 was dragged onto the second Space.
    tracker.observe(onScreen: [3, 4, 1], on: 1)

    #expect(tracker.spaceIndex(of: 1, on: 1) == 1)
    #expect(tracker.knownSpaceCount(on: 1) == 2)
  }

  @Test("The Space sharing the most windows is the one being looked at")
  func matchesTheSpaceWithTheLargestOverlap() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2, 3], on: 1)
    tracker.observe(onScreen: [4, 5], on: 1)
    // Shares one window with the first Space and both with the second.
    tracker.observe(onScreen: [3, 4, 5], on: 1)

    #expect(tracker.knownSpaceCount(on: 1) == 2)
    #expect(tracker.spaceIndex(of: 3, on: 1) == 1)
  }

  @Test("Displays are learned independently")
  func displaysAreIndependent() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1], on: 1)
    tracker.observe(onScreen: [2], on: 2)

    #expect(tracker.spaceIndex(of: 1, on: 1) == 0)
    #expect(tracker.spaceIndex(of: 2, on: 2) == 0)
    #expect(tracker.knownSpaceCount(on: 1) == 1)
    #expect(tracker.knownSpaceCount(on: 2) == 1)
  }

  @Test("An empty screen teaches nothing")
  func emptyObservationIsIgnored() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [], on: 1)

    #expect(tracker.knownSpaceCount(on: 1) == 0)
  }

  @Test("Closed windows are forgotten")
  func closedWindowsAreForgotten() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1, 2], on: 1)

    tracker.retain(windowIDs: [1])

    #expect(tracker.spaceIndex(of: 1, on: 1) == 0)
    #expect(tracker.spaceIndex(of: 2, on: 1) == nil)
  }

  @Test("Emptying a Space does not renumber the ones after it")
  func emptiedSpacesKeepTheirNumber() {
    var tracker = SpaceTracker()
    tracker.observe(onScreen: [1], on: 1)
    tracker.observe(onScreen: [2], on: 1)

    tracker.retain(windowIDs: [2])

    #expect(tracker.spaceIndex(of: 2, on: 1) == 1)
    #expect(tracker.knownSpaceCount(on: 1) == 2)
  }
}
