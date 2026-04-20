import CoreGraphics
import Foundation

@MainActor
final class WorkspacePreviewCache {
    private let fullSnapshotStaleSeconds: TimeInterval
    private let windowThumbnailsStaleSeconds: TimeInterval

    private var entries: [String: WorkspacePreviewCacheEntry] = [:]

    init(config: AppConfig = .default) {
        self.fullSnapshotStaleSeconds = config.fullSnapshotStaleSeconds
        self.windowThumbnailsStaleSeconds = config.windowThumbnailsStaleSeconds
    }

    func storeWorkspaceIDs(_ workspaceIDs: [String]) {
        for workspaceID in workspaceIDs {
            entry(for: workspaceID)
        }
    }

    func storeFullSnapshot(_ image: CGImage, for workspaceID: String, updatedAt: Date = Date()) {
        var entry = entry(for: workspaceID)
        entry.fullSnapshot = image
        entry.fullSnapshotUpdatedAt = updatedAt
        entries[workspaceID] = entry
    }

    func storeWindowThumbnails(
        _ thumbnails: [String: CGImage],
        groupedByWorkspace requestWorkspaceIDs: [String: String],
        updatedAt: Date = Date()
    ) {
        let grouped = Dictionary(grouping: thumbnails.keys, by: { previewID in
            requestWorkspaceIDs[previewID] ?? ""
        })

        for (workspaceID, previewIDs) in grouped where !workspaceID.isEmpty {
            var entry = entry(for: workspaceID)
            entry.windowThumbnails = previewIDs.reduce(into: [:]) { partialResult, previewID in
                partialResult[previewID] = thumbnails[previewID]
            }
            entry.windowThumbnailsUpdatedAt = updatedAt
            entries[workspaceID] = entry
        }
    }

    func fullSnapshot(for workspaceID: String) -> CGImage? {
        entries[workspaceID]?.fullSnapshot
    }

    func windowThumbnail(for workspaceID: String, previewID: String) -> CGImage? {
        entries[workspaceID]?.windowThumbnails[previewID]
    }

    func source(for workspaceID: String, previewIDs: [String]) -> WorkspacePreviewSource {
        guard let entry = entries[workspaceID] else {
            return .fallback
        }

        if entry.fullSnapshot != nil {
            return .full
        }

        if previewIDs.contains(where: { entry.windowThumbnails[$0] != nil }) {
            return .composite
        }

        return .fallback
    }

    func isStale(workspaceID: String, source: WorkspacePreviewSource, now: Date = Date()) -> Bool {
        guard let entry = entries[workspaceID] else {
            return false
        }

        switch source {
        case .full:
            guard let updatedAt = entry.fullSnapshotUpdatedAt else {
                return false
            }

            return now.timeIntervalSince(updatedAt) > fullSnapshotStaleSeconds

        case .composite:
            guard let updatedAt = entry.windowThumbnailsUpdatedAt else {
                return false
            }

            return now.timeIntervalSince(updatedAt) > windowThumbnailsStaleSeconds

        case .fallback:
            return false
        }
    }

    func clear() {
        entries.removeAll()
    }

    @discardableResult
    private func entry(for workspaceID: String) -> WorkspacePreviewCacheEntry {
        if let existing = entries[workspaceID] {
            return existing
        }

        let created = WorkspacePreviewCacheEntry(workspaceID: workspaceID)
        entries[workspaceID] = created
        return created
    }
}

private struct WorkspacePreviewCacheEntry {
    let workspaceID: String
    var fullSnapshot: CGImage?
    var windowThumbnails: [String: CGImage] = [:]
    var fullSnapshotUpdatedAt: Date?
    var windowThumbnailsUpdatedAt: Date?
}
