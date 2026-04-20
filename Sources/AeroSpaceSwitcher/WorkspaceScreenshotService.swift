import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class WorkspaceScreenshotService {
    private let targetSnapshotSize: CGSize
    private let logger: AppLogger

    init(config: AppConfig = .default) {
        self.targetSnapshotSize = config.fullSnapshotTargetSize
        self.logger = AppLogger(debugMode: config.debugMode, category: .capture)
    }

    func captureFocusedWorkspaceSnapshot() async -> CGImage? {
        guard #available(macOS 14.0, *) else {
            logger.warning("Full workspace snapshots require macOS 14 or newer")
            return nil
        }

        do {
            let content = try await SCShareableContent.current
            guard let display = selectDisplay(from: content.displays) else {
                logger.warning("No ScreenCaptureKit display available for full snapshot")
                return nil
            }

            logger.debug("Capturing full workspace snapshot")
            return try await captureDisplaySnapshot(display)
        } catch {
            logger.error("Full workspace snapshot unavailable: \(error)")
            return nil
        }
    }

    @available(macOS 14.0, *)
    private func captureDisplaySnapshot(_ display: SCDisplay) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(targetSnapshotSize.width)
        configuration.height = Int(targetSnapshotSize.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsDisplay = true

        let filter = SCContentFilter(display: display, excludingWindows: [])

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                continuation.resume(
                    throwing: error ?? WorkspaceScreenshotError.missingImage
                )
            }
        }
    }

    @available(macOS 14.0, *)
    private func selectDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        guard let screenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber else {
            return displays.first
        }

        let mainDisplayID = CGDirectDisplayID(screenNumber.uint32Value)
        return displays.first(where: { $0.displayID == mainDisplayID }) ?? displays.first
    }
}

enum WorkspaceScreenshotError: Error, CustomStringConvertible {
    case missingImage

    var description: String {
        switch self {
        case .missingImage:
            return "ScreenCaptureKit did not return a full workspace image"
        }
    }
}
