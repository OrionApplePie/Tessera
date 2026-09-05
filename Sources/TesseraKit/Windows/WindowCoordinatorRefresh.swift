import Foundation

// MARK: - One refresh at a time

/// Keeping two refreshes from running at once.
///
/// A refresh is one window enumeration and one pass of captures, and two of them
/// answer the same question twice. Measured on closing the overlay, which asks for
/// a fresh list while the timer's own is already in flight: two enumerations and
/// two capture passes, back to back, for one answer.
extension WindowCoordinator {
  /// Whether this refresh should go ahead, or fold into the one already running.
  func startRefresh(capturingThumbnails: Bool) -> Bool {
    guard !isRefreshing else {
      // The one already running is at most a moment old. Only a request for
      // thumbnails it is not taking is worth a second pass — and then just one.

      wantsAnotherRefresh =
        wantsAnotherRefresh || (capturingThumbnails && !refreshingWithThumbnails)
      return false
    }

    isRefreshing = true
    refreshingWithThumbnails = capturingThumbnails

    return true
  }

  /// Lets the next one through, and runs the one that was folded in if it asked for
  /// something this one did not do.
  func endRefresh() {
    isRefreshing = false

    guard wantsAnotherRefresh else {
      return
    }

    wantsAnotherRefresh = false

    Task { @MainActor [weak self] in
      await self?.refreshNow()
    }
  }
}
