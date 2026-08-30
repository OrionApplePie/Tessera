import CoreGraphics
import Foundation
import Testing

@testable import Tessera

/// Capture itself needs ScreenCaptureKit and a real screen. What is testable is
/// the bookkeeping that keeps one wedged window from stalling every refresh.
@Suite("UnresponsiveWindowTracker")
struct UnresponsiveWindowTrackerTests {
  private let markedAt = Date(timeIntervalSince1970: 1_700_000_000)

  @Test("A window nobody has given up on is captured")
  func unknownWindowsAreNotSkipped() {
    var tracker = UnresponsiveWindowTracker()

    #expect(tracker.shouldSkip(1, now: markedAt) == false)
  }

  @Test("A window that timed out is skipped for the whole cooldown")
  func skipsAnUnresponsiveWindow() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, at: markedAt)

    #expect(tracker.shouldSkip(1, now: markedAt) == true)
    #expect(tracker.shouldSkip(1, now: markedAt.addingTimeInterval(299)) == true)
  }

  @Test("Giving up on one window does not affect the others")
  func skipsOnlyTheMarkedWindow() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, at: markedAt)

    #expect(tracker.shouldSkip(2, now: markedAt) == false)
  }

  @Test("After the cooldown the window gets another chance")
  func retriesAfterTheCooldown() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, at: markedAt)

    #expect(tracker.shouldSkip(1, now: markedAt.addingTimeInterval(300)) == false)
  }

  @Test("An expired entry is dropped rather than kept forever")
  func expiredEntriesAreForgotten() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, at: markedAt)
    #expect(tracker.skippedCount == 1)

    _ = tracker.shouldSkip(1, now: markedAt.addingTimeInterval(300))

    #expect(tracker.skippedCount == 0)
  }

  @Test("A window that times out again restarts its cooldown")
  func remarkingRestartsTheCooldown() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, at: markedAt)

    let later = markedAt.addingTimeInterval(400)
    #expect(tracker.shouldSkip(1, now: later) == false)
    tracker.markUnresponsive(1, at: later)

    #expect(tracker.shouldSkip(1, now: later.addingTimeInterval(10)) == true)
  }
}
