import CoreGraphics
import Foundation

/// In-memory only. Thumbnails are never written to disk.
@MainActor
final class WindowPreviewCache {
  private let windowThumbnailsStaleSeconds: TimeInterval

  private var entries: [CGWindowID: WindowPreviewCacheEntry] = [:]

  init(config: AppConfig = .default) {
    self.windowThumbnailsStaleSeconds = config.windowThumbnailsStaleSeconds
  }

  func storeThumbnails(_ thumbnails: [CGWindowID: CGImage], updatedAt: Date = Date()) {
    for (windowID, image) in thumbnails {
      entries[windowID] = WindowPreviewCacheEntry(thumbnail: image, updatedAt: updatedAt)
    }
  }

  func thumbnail(for windowID: CGWindowID) -> CGImage? {
    entries[windowID]?.thumbnail
  }

  func isStale(windowID: CGWindowID, now: Date = Date()) -> Bool {
    guard let entry = entries[windowID] else {
      return false
    }

    return now.timeIntervalSince(entry.updatedAt) > windowThumbnailsStaleSeconds
  }

  /// Drops cached previews for windows that have since closed, so a long-running
  /// session does not accumulate images for windows nobody can switch to.
  func retain(windowIDs: [CGWindowID]) {
    let live = Set(windowIDs)
    entries = entries.filter { live.contains($0.key) }
  }

  func clear() {
    entries.removeAll()
  }
}

private struct WindowPreviewCacheEntry {
  let thumbnail: CGImage
  let updatedAt: Date
}
