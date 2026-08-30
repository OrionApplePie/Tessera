import CoreGraphics
import Foundation
import Testing

@testable import Tessera

@Suite("WindowPreviewCache")
@MainActor
struct WindowPreviewCacheTests {
  private let storedAt = Date(timeIntervalSince1970: 1_700_000_000)

  @Test("A stored thumbnail is returned for its own window and for no other")
  func storesThumbnailsByWindowID() throws {
    let cache = makeCache()
    let image = try makeImage()

    cache.storeThumbnails([1: image], updatedAt: storedAt)

    #expect(cache.thumbnail(for: 1) === image)
    #expect(cache.thumbnail(for: 2) == nil)
  }

  @Test("Storing again for the same window replaces the previous thumbnail")
  func replacesAnExistingThumbnail() throws {
    let cache = makeCache()
    let old = try makeImage()
    let new = try makeImage()

    cache.storeThumbnails([1: old], updatedAt: storedAt)
    cache.storeThumbnails([1: new], updatedAt: storedAt)

    #expect(cache.thumbnail(for: 1) === new)
  }

  @Test("A window with no cached thumbnail is not reported as stale")
  func treatsUnknownWindowsAsFresh() {
    #expect(makeCache().isStale(windowID: 1, now: storedAt) == false)
  }

  @Test("A thumbnail goes stale only after the configured interval has passed")
  func reportsStalenessAgainstTheConfiguredInterval() throws {
    let cache = makeCache(staleAfter: 30)
    cache.storeThumbnails([1: try makeImage()], updatedAt: storedAt)

    #expect(cache.isStale(windowID: 1, now: storedAt) == false)
    #expect(cache.isStale(windowID: 1, now: storedAt.addingTimeInterval(29)) == false)
    #expect(cache.isStale(windowID: 1, now: storedAt.addingTimeInterval(30)) == false)
    #expect(cache.isStale(windowID: 1, now: storedAt.addingTimeInterval(30.001)) == true)
  }

  @Test("Retaining live windows drops previews for windows that have closed")
  func dropsPreviewsForClosedWindows() throws {
    let cache = makeCache()
    let image = try makeImage()

    cache.storeThumbnails([1: image, 2: image, 3: image], updatedAt: storedAt)
    cache.retain(windowIDs: [1, 3])

    #expect(cache.thumbnail(for: 1) === image)
    #expect(cache.thumbnail(for: 2) == nil)
    #expect(cache.thumbnail(for: 3) === image)
  }

  @Test("Retaining an empty window list empties the cache")
  func retainingNothingEmptiesTheCache() throws {
    let cache = makeCache()
    cache.storeThumbnails([1: try makeImage()], updatedAt: storedAt)

    cache.retain(windowIDs: [])

    #expect(cache.thumbnail(for: 1) == nil)
  }

  @Test("Clearing drops every preview, so quitting leaves no images in memory")
  func clearDropsEveryPreview() throws {
    let cache = makeCache()
    let image = try makeImage()
    cache.storeThumbnails([1: image, 2: image], updatedAt: storedAt)

    cache.clear()

    #expect(cache.thumbnail(for: 1) == nil)
    #expect(cache.thumbnail(for: 2) == nil)
  }

  // MARK: - Helpers

  private func makeCache(staleAfter staleSeconds: TimeInterval = 30) -> WindowPreviewCache {
    var config = AppConfig.default
    config.windowThumbnailsStaleSeconds = staleSeconds
    return WindowPreviewCache(config: config)
  }

  private func makeImage() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )

    return try #require(context.makeImage())
  }
}
