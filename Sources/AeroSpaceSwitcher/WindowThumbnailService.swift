import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class WindowThumbnailService {
    private let targetThumbnailSize: CGSize
    private let logger: AppLogger

    init(config: AppConfig = .default) {
        self.targetThumbnailSize = config.windowThumbnailTargetSize
        self.logger = AppLogger(debugMode: config.debugMode, category: .capture)
    }

    func thumbnails(for requests: [WindowPreviewRequest]) async -> [String: CGImage] {
        guard !requests.isEmpty else {
            return [:]
        }

        guard #available(macOS 14.0, *) else {
            logger.warning("Window thumbnails require macOS 14 or newer")
            return [:]
        }

        do {
            let content = try await SCShareableContent.current
            let matcher = ScreenCaptureWindowMatcher(windows: content.windows)
            var usedWindowIDs = Set<CGWindowID>()
            var result: [String: CGImage] = [:]

            for request in requests {
                guard let window = matcher.bestMatch(for: request.window, excluding: usedWindowIDs) else {
                    logger.debug("No ScreenCaptureKit match for a requested window")
                    continue
                }

                usedWindowIDs.insert(window.windowID)

                do {
                    result[request.id] = try await captureThumbnail(for: window)
                } catch {
                    logger.warning("Failed to capture a window thumbnail: \(error)")
                }
            }

            logger.debug("Captured \(result.count) window thumbnails")
            return result
        } catch {
            logger.error("ScreenCaptureKit content unavailable: \(error)")
            return [:]
        }
    }

    @available(macOS 14.0, *)
    private func captureThumbnail(for window: SCWindow) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        let outputSize = scaledOutputSize(for: window.frame.size)

        configuration.width = Int(outputSize.width)
        configuration.height = Int(outputSize.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = true

        let filter = SCContentFilter(desktopIndependentWindow: window)

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                continuation.resume(
                    throwing: error ?? WindowThumbnailError.missingImage
                )
            }
        }
    }

    private func scaledOutputSize(for sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return targetThumbnailSize
        }

        let scale = min(
            targetThumbnailSize.width / sourceSize.width,
            targetThumbnailSize.height / sourceSize.height
        )
        let boundedScale = min(max(scale, 0.1), 1.0)

        return CGSize(
            width: max(1, floor(sourceSize.width * boundedScale)),
            height: max(1, floor(sourceSize.height * boundedScale))
        )
    }
}

enum WindowThumbnailError: Error, CustomStringConvertible {
    case missingImage

    var description: String {
        switch self {
        case .missingImage:
            return "ScreenCaptureKit did not return an image"
        }
    }
}

@available(macOS 14.0, *)
private struct ScreenCaptureWindowMatcher {
    private let windows: [SCWindow]

    init(windows: [SCWindow]) {
        self.windows = windows.filter { window in
            window.windowLayer == 0
                && window.frame.width > 20
                && window.frame.height > 20
        }
    }

    func bestMatch(for aeroSpaceWindow: AeroSpaceWindow, excluding usedWindowIDs: Set<CGWindowID>) -> SCWindow? {
        windows
            .filter { !usedWindowIDs.contains($0.windowID) }
            .compactMap { window -> MatchCandidate? in
                let score = matchScore(aeroSpaceWindow: aeroSpaceWindow, screenCaptureWindow: window)
                guard score >= 80 else {
                    return nil
                }

                return MatchCandidate(window: window, score: score)
            }
            .sorted { first, second in
                if first.score != second.score {
                    return first.score > second.score
                }

                return first.window.frame.area > second.window.frame.area
            }
            .first?
            .window
    }

    private func matchScore(aeroSpaceWindow: AeroSpaceWindow, screenCaptureWindow: SCWindow) -> Int {
        let targetApp = normalize(aeroSpaceWindow.appName)
        let targetTitle = normalize(aeroSpaceWindow.title)
        let candidateApp = normalize(screenCaptureWindow.owningApplication?.applicationName ?? "")
        let candidateTitle = normalize(screenCaptureWindow.title ?? "")

        var score = 0

        if !targetApp.isEmpty, targetApp == candidateApp {
            score += 100
        } else if containsEither(targetApp, candidateApp) {
            score += 60
        }

        if !targetTitle.isEmpty, targetTitle == candidateTitle {
            score += 100
        } else if containsEither(targetTitle, candidateTitle) {
            score += 45
        }

        if screenCaptureWindow.isOnScreen {
            score += 10
        }

        if screenCaptureWindow.frame.area > 20_000 {
            score += 5
        }

        return score
    }

    private func containsEither(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return false
        }

        return lhs.contains(rhs) || rhs.contains(lhs)
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

@available(macOS 14.0, *)
private struct MatchCandidate {
    let window: SCWindow
    let score: Int
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}
