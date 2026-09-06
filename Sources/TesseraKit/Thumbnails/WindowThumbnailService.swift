import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures a thumbnail per window, addressed by `CGWindowID`.
///
/// Because `WindowListService` hands out the same ids ScreenCaptureKit uses,
/// lookup here is an exact match — there is no heuristic scoring to get wrong.
@MainActor
final class WindowThumbnailService {
  /// A capture normally answers in well under 200ms. Some windows never answer at
  /// all — a minimized window of an app that has stopped rendering, for instance —
  /// and ScreenCaptureKit neither returns nor errors for those.
  private let captureTimeout: Duration

  /// The tile a capture is sized for.
  private let captureTile: TileMetrics
  private let quality: ThumbnailQuality
  private let mode: WindowThumbnailMode
  private let takesLongWindowsWhole: Bool
  private let logger: AppLogger
  private var unresponsiveWindows = UnresponsiveWindowTracker()

  init(config: AppConfig = .default) {
    // A screen-filling overlay draws tiles as large as the screen allows, so the
    // capture is made for the largest tile there can be. Sized for the small tile,
    // the picture was soft the moment the overlay filled a 27-inch display.
    // Sized for a large tile rather than for the largest one there can be: the
    // biggest layouts are two or three tiles filling a screen, and capturing every
    // window for that case costs memory on every window that is never drawn that
    // large. `window_thumbnail_quality` is the knob for those who want it sharper.
    self.captureTile = config.overlayFillsScreen ? TileMetrics(width: 360) : .base
    self.quality = config.thumbnailQuality
    self.mode = config.windowThumbnailMode
    self.takesLongWindowsWhole = config.capturesLongWindowsWhole
    self.captureTimeout = .seconds(config.unresponsiveAfterSeconds)
    self.logger = AppLogger(debugMode: config.debugMode, category: .capture)
  }

  func thumbnails(for windowIDs: [CGWindowID]) async -> [CGWindowID: CGImage] {
    guard !windowIDs.isEmpty else {
      return [:]
    }

    guard #available(macOS 14.0, *) else {
      logger.warning("Window thumbnails require macOS 14 or newer")
      return [:]
    }

    let requested = Set(windowIDs)

    do {
      let content = try await SCShareableContent.current
      var result: [CGWindowID: CGImage] = [:]

      for window in content.windows where requested.contains(window.windowID) {
        // A window that is not on screen has nothing to copy: it is on another Space
        // or minimized, and the capture does not fail — it hangs until the timeout.
        // Measured from an empty desktop, where nothing is on screen at all:
        // twenty-one windows, two seconds each, three quarters of a minute of
        // grinding, and a map of name-only tiles at the end of it. What such a
        // window shows is the picture taken when it was last visible, which the
        // cache is holding already.
        guard window.isOnScreen else {
          continue
        }

        guard !unresponsiveWindows.shouldSkip(window.windowID, isOnScreen: window.isOnScreen)
        else {
          continue
        }

        do {
          result[window.windowID] = try await captureThumbnail(for: window)
        } catch WindowThumbnailError.timedOut {
          unresponsiveWindows.markUnresponsive(
            window.windowID, isOnScreen: window.isOnScreen)
          logger.warning(
            "Window \(window.windowID) did not answer a thumbnail capture; "
              + "skipping it for now and showing a name-only tile"
          )
        } catch {
          logger.warning("Failed to capture a window thumbnail: \(error)")
        }
      }

      logger.debug(
        "Captured \(result.count) of \(requested.count) window thumbnails at "
          + "\(Int(backingScaleFactor))x, "
          + "\(unresponsiveWindows.skippedCount) window(s) skipped as unresponsive"
      )
      return result
    } catch {
      logger.error("ScreenCaptureKit content unavailable: \(error)")
      return [:]
    }
  }

  /// Captures one window, giving up after `captureTimeout`.
  ///
  /// The capture runs in its own task rather than as a child of a task group,
  /// because a group awaits every child before it returns: one call that never
  /// answers would hang the whole refresh, which is exactly the bug this guards.
  /// A timed-out capture is therefore abandoned rather than awaited, and the
  /// window is skipped from then on so nothing is abandoned twice.
  @available(macOS 14.0, *)
  private func captureThumbnail(for window: SCWindow) async throws -> CGImage {
    let outcome = await withCheckedContinuation { continuation in
      let resume = ResumeOnce(continuation)

      let capture = Task { @MainActor in
        do {
          resume(.image(try await captureUnbounded(for: window)))
        } catch {
          resume(.failed(error))
        }
      }

      let timeout = captureTimeout
      Task { @MainActor in
        try? await Task.sleep(for: timeout)
        capture.cancel()
        resume(.timedOut)
      }
    }

    switch outcome {
    case .image(let image):
      return image
    case .failed(let error):
      throw error
    case .timedOut:
      throw WindowThumbnailError.timedOut
    }
  }

  @available(macOS 14.0, *)
  private func captureUnbounded(for window: SCWindow) async throws -> CGImage {
    let configuration = configuration(for: window.frame.size)
    let filter = SCContentFilter(desktopIndependentWindow: window)

    return try await withCheckedThrowingContinuation { continuation in
      SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
      ) { image, error in
        if let image {
          continuation.resume(returning: image)
          return
        }

        continuation.resume(throwing: error ?? WindowThumbnailError.missingImage)
      }
    }
  }

  /// How the window is asked for: the whole of it, or one corner of it.
  ///
  /// A corner is taken through `sourceRect`, which for a window filter is measured
  /// in points from the window's own top left — not from the screen's, though the
  /// filter reports the window's global frame as its content rect. Nothing is
  /// scaled: the crop is exactly the area the tile draws, so the pixels captured
  /// are the pixels shown.
  @available(macOS 14.0, *)
  private func configuration(for windowSize: CGSize) -> SCStreamConfiguration {
    let mode = WindowThumbnailMode.capturing(
      windowSize, wanted: mode,
      tile: CGSize(width: captureTile.width, height: captureTile.thumbnailHeight),
      takingLongWindowsWhole: takesLongWindowsWhole)
    let configuration = SCStreamConfiguration()
    configuration.showsCursor = false
    configuration.ignoreShadowsSingleWindow = true
    configuration.shouldBeOpaque = true
    configuration.preservesAspectRatio = true

    switch mode {
    case .fit:
      let outputSize = outputSize(for: windowSize)
      configuration.width = Int(outputSize.width)
      configuration.height = Int(outputSize.height)
      configuration.scalesToFit = true
    case .corner, .cornerDouble, .quarter, .threeQuarters:
      let crop = Self.cornerCrop(forWindowSize: windowSize, mode: mode, tile: captureTile)
      // Asked for in pixels rather than in points: the piece of the window is the
      // same either way, and how sharp it lands on a large tile is exactly what the
      // quality setting decides.
      let scale = quality.scale(forCrop: crop, onScreenScale: backingScaleFactor)
      configuration.sourceRect = CGRect(origin: .zero, size: crop)
      configuration.width = Int(max(1, crop.width * scale))
      configuration.height = Int(max(1, crop.height * scale))
      configuration.scalesToFit = false
    }

    return configuration
  }

  /// The piece of a window a corner thumbnail shows.
  ///
  /// Measured against the tile's own drawing area, so that `corner` is drawn at its
  /// own size — that is the whole point of that mode — and the wider modes are an
  /// honest multiple of it.
  nonisolated static func cornerCrop(
    forWindowSize size: CGSize,
    mode: WindowThumbnailMode,
    tile: TileMetrics = .base
  ) -> CGSize {
    mode.crop(
      ofWindow: size,
      // Captured for the largest tile the overlay can draw rather than for the one
      // it happens to be drawing: the tile is a function of the screen, and a
      // capture made for a small tile is a soft picture on a large one — while the
      // same capture scaled down loses nothing.
      tile: CGSize(width: tile.contentWidth, height: tile.thumbnailHeight)
    )
  }

  /// What a whole-window thumbnail is captured for: the tile the map can draw it
  /// in, widened to whatever the quality setting asks for.
  ///
  /// The tile is not a number anybody types any more — the map sizes it from the
  /// screen and from how many Spaces there are — so the capture follows the largest
  /// tile the overlay may use rather than a figure in the config that had no way of
  /// knowing. The quality setting is what buys more pixels than that.
  private var targetForQuality: CGSize {
    let targetThumbnailSize = CGSize(
      width: captureTile.contentWidth, height: captureTile.thumbnailHeight)
    let longest = max(targetThumbnailSize.width, targetThumbnailSize.height)
    let wanted = quality.longSide / backingScaleFactor

    guard longest > 0, wanted > longest else {
      return targetThumbnailSize
    }

    let factor = wanted / longest

    return CGSize(
      width: targetThumbnailSize.width * factor,
      height: targetThumbnailSize.height * factor
    )
  }

  /// The capture size in pixels for a window measured in points.
  ///
  /// `SCStreamConfiguration` counts pixels, the target size in the config counts
  /// points, and a Retina display draws two pixels per point. Capturing at the
  /// point size therefore produced an image at half the density the tile is drawn
  /// at, which the view then stretched — the thumbnails looked soft for exactly
  /// that reason.
  ///
  /// A window is never captured larger than it is: upscaling adds no detail, only
  /// bytes.
  private func outputSize(for sourceSize: CGSize) -> CGSize {
    let scale = backingScaleFactor
    let target = targetForQuality
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return CGSize(width: target.width * scale, height: target.height * scale)
    }

    let sourcePixels = CGSize(
      width: sourceSize.width * scale,
      height: sourceSize.height * scale
    )
    let ratio = min(
      target.width * scale / sourcePixels.width,
      target.height * scale / sourcePixels.height,
      1
    )

    return CGSize(
      width: max(1, floor(sourcePixels.width * ratio)),
      height: max(1, floor(sourcePixels.height * ratio))
    )
  }

  /// The densest screen attached: a window can be dragged between displays, and a
  /// thumbnail captured for the coarser one looks soft on the finer.
  private var backingScaleFactor: CGFloat {
    NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
  }

}

/// Remembers windows whose capture never came back, and gives one another chance
/// when it returns to the screen.
///
/// A capture hangs because the window has no surface to capture — a minimized
/// window of an application that has stopped drawing. That is not a state which
/// ends after some number of minutes, it ends when the window is on screen again,
/// and the window server says so on every refresh. Waiting for that is exact, where
/// a cooldown was a guess in both directions: too long to notice a window that came
/// straight back, too short to stop paying for one that never would.
struct UnresponsiveWindowTracker {
  /// The marked windows, each with whether it has been seen off screen since.
  private var seenOffScreen: [CGWindowID: Bool] = [:]

  var skippedCount: Int {
    seenOffScreen.count
  }

  mutating func markUnresponsive(_ windowID: CGWindowID, isOnScreen: Bool) {
    seenOffScreen[windowID] = !isOnScreen
  }

  /// Whether this window should be left alone for now.
  ///
  /// A window that has been off screen since it was marked and is on screen now has
  /// a surface again, and is asked again. One that hung while on screen has to leave
  /// the screen first: otherwise a wedged window in plain sight would cost the whole
  /// timeout on every refresh, which is the bug the tracker exists to prevent.
  mutating func shouldSkip(_ windowID: CGWindowID, isOnScreen: Bool) -> Bool {
    guard let wasOffScreen = seenOffScreen[windowID] else {
      return false
    }

    guard isOnScreen else {
      seenOffScreen[windowID] = true
      return true
    }

    guard wasOffScreen else {
      return true
    }

    seenOffScreen[windowID] = nil
    return false
  }
}

/// Delivers the first of a capture and its timeout, and ignores whichever loses.
@MainActor
private final class ResumeOnce {
  private var continuation: CheckedContinuation<CaptureOutcome, Never>?

  init(_ continuation: CheckedContinuation<CaptureOutcome, Never>) {
    self.continuation = continuation
  }

  func callAsFunction(_ outcome: CaptureOutcome) {
    continuation?.resume(returning: outcome)
    continuation = nil
  }
}

private enum CaptureOutcome {
  case image(CGImage)
  case failed(Error)
  case timedOut
}

enum WindowThumbnailError: Error, CustomStringConvertible {
  case missingImage
  case timedOut

  var description: String {
    switch self {
    case .missingImage:
      return "ScreenCaptureKit did not return an image"
    case .timedOut:
      return "ScreenCaptureKit did not answer a thumbnail capture in time"
    }
  }
}
