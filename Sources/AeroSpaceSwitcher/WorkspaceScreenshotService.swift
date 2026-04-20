import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class WorkspaceScreenshotService {
    private let targetSnapshotSize: CGSize

    init(config: AppConfig = .default) {
        self.targetSnapshotSize = config.fullSnapshotTargetSize
    }

    func captureFocusedWorkspaceSnapshot() async -> CGImage? {
        guard #available(macOS 14.0, *) else {
            fputs("AeroSpaceSwitcher: full workspace snapshots require macOS 14 or newer\n", stderr)
            return nil
        }

        do {
            let content = try await SCShareableContent.current
            guard let display = selectDisplay(from: content.displays) else {
                fputs("AeroSpaceSwitcher: no ScreenCaptureKit display available for full snapshot\n", stderr)
                return nil
            }

            return try await captureDisplaySnapshot(display)
        } catch {
            fputs("AeroSpaceSwitcher: full workspace snapshot unavailable: \(error)\n", stderr)
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
