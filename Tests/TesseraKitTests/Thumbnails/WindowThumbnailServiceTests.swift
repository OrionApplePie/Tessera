import CoreGraphics
import Foundation
import Testing

@testable import TesseraKit

/// Capture itself needs ScreenCaptureKit and a real screen. What is testable is
/// the bookkeeping that keeps one wedged window from stalling every refresh.
@Suite("UnresponsiveWindowTracker")
struct UnresponsiveWindowTrackerTests {
  private let markedAt = Date(timeIntervalSince1970: 1_700_000_000)

  @Test("A window nobody has given up on is captured")
  func capturesAWindowNobodyGaveUpOn() {
    var tracker = UnresponsiveWindowTracker()

    #expect(tracker.shouldSkip(1, isOnScreen: true) == false)
  }

  @Test("A window that timed out is left alone while it stays off screen")
  func skipsAnUnresponsiveWindow() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, isOnScreen: false)

    #expect(tracker.shouldSkip(1, isOnScreen: false) == true)
    #expect(tracker.shouldSkip(1, isOnScreen: false) == true)
  }

  @Test("Giving up on one window does not affect the others")
  func skipsOnlyTheMarkedWindow() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, isOnScreen: false)

    #expect(tracker.shouldSkip(2, isOnScreen: false) == false)
  }

  /// A capture hangs when the window has no surface, which is what being off
  /// screen means. Coming back is the event that makes it worth asking again.
  @Test("A window that comes back on screen gets another chance")
  func retriesAWindowThatCameBack() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, isOnScreen: false)

    #expect(tracker.shouldSkip(1, isOnScreen: true) == false)
  }

  @Test("Its chance is not spent twice over")
  func forgetsAWindowItHasGivenBack() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, isOnScreen: false)
    _ = tracker.shouldSkip(1, isOnScreen: true)

    #expect(tracker.shouldSkip(1, isOnScreen: false) == false)
    #expect(tracker.skippedCount == 0)
  }

  /// Otherwise a wedged window in plain sight would be asked again on every
  /// refresh, and cost the whole timeout each time — which is the stall the
  /// tracker exists to prevent.
  @Test("A window that hung in plain sight has to leave the screen first")
  func makesAWindowLeaveTheScreenBeforeTryingAgain() {
    var tracker = UnresponsiveWindowTracker()
    tracker.markUnresponsive(1, isOnScreen: true)

    #expect(tracker.shouldSkip(1, isOnScreen: true) == true)
    #expect(tracker.shouldSkip(1, isOnScreen: false) == true)
    #expect(tracker.shouldSkip(1, isOnScreen: true) == false)
  }

  @Test("A corner thumbnail crops exactly what the tile draws")
  func cropsWhatTheTileDraws() {
    let crop = WindowThumbnailService.cornerCrop(
      forWindowSize: CGSize(width: 1512, height: 944), mode: .corner)

    #expect(crop.width == TileMetrics.base.contentWidth)
    #expect(crop.height == TileMetrics.base.thumbnailHeight)
  }

  @Test("A wider mode asks for more of the window, in the same proportions")
  func cropsMoreForAWiderMode() {
    let window = CGSize(width: 1512, height: 944)
    let corner = WindowThumbnailService.cornerCrop(forWindowSize: window, mode: .corner)
    let double = WindowThumbnailService.cornerCrop(forWindowSize: window, mode: .cornerDouble)

    #expect(double.width == corner.width * 2)
    #expect(double.height == corner.height * 2)
  }

  @Test("A window smaller than the tile is taken whole rather than padded")
  func takesASmallWindowWhole() {
    let crop = WindowThumbnailService.cornerCrop(
      forWindowSize: CGSize(width: 80, height: 60), mode: .corner)

    #expect(crop == CGSize(width: 80, height: 60))
  }

  @Test("A window with no size still asks for something capturable")
  func neverAsksForNothing() {
    let crop = WindowThumbnailService.cornerCrop(forWindowSize: .zero, mode: .quarter)

    #expect(crop.width >= 1)
    #expect(crop.height >= 1)
  }

}
