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
  private static let captureTimeout = Duration.seconds(2)

  private let targetThumbnailSize: CGSize
  private let logger: AppLogger
  private var unresponsiveWindows = UnresponsiveWindowTracker()

  init(config: AppConfig = .default) {
    self.targetThumbnailSize = config.windowThumbnailTargetSize
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
        guard !unresponsiveWindows.shouldSkip(window.windowID) else {
          continue
        }

        do {
          result[window.windowID] = try await captureThumbnail(for: window)
        } catch WindowThumbnailError.timedOut {
          unresponsiveWindows.markUnresponsive(window.windowID)
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

      Task { @MainActor in
        try? await Task.sleep(for: Self.captureTimeout)
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
    let configuration = SCStreamConfiguration()
    let outputSize = outputSize(for: window.frame.size)

    configuration.width = Int(outputSize.width)
    configuration.height = Int(outputSize.height)
    configuration.showsCursor = false
    configuration.scalesToFit = true
    configuration.preservesAspectRatio = true
    configuration.ignoreShadowsSingleWindow = true
    configuration.shouldBeOpaque = true

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
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return CGSize(
        width: targetThumbnailSize.width * scale,
        height: targetThumbnailSize.height * scale
      )
    }

    let sourcePixels = CGSize(
      width: sourceSize.width * scale,
      height: sourceSize.height * scale
    )
    let ratio = min(
      targetThumbnailSize.width * scale / sourcePixels.width,
      targetThumbnailSize.height * scale / sourcePixels.height,
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

/// Remembers windows whose capture never came back, so they are asked at most
/// once per cooldown instead of stalling every refresh.
struct UnresponsiveWindowTracker {
  /// Long enough that a wedged window stops costing anything, short enough that a
  /// window which merely was not rendering yet gets another chance.
  static let cooldown: TimeInterval = 300

  private var markedAt: [CGWindowID: Date] = [:]

  var skippedCount: Int {
    markedAt.count
  }

  mutating func markUnresponsive(_ windowID: CGWindowID, at date: Date = Date()) {
    markedAt[windowID] = date
  }

  mutating func shouldSkip(_ windowID: CGWindowID, now: Date = Date()) -> Bool {
    guard let markedAt = markedAt[windowID] else {
      return false
    }

    guard now.timeIntervalSince(markedAt) < Self.cooldown else {
      self.markedAt[windowID] = nil
      return false
    }

    return true
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
