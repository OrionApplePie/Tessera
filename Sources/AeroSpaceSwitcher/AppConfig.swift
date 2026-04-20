import CoreGraphics
import Foundation

struct AppConfig {
    var refreshIntervalSeconds: TimeInterval
    var fullSnapshotStaleSeconds: TimeInterval
    var windowThumbnailsStaleSeconds: TimeInterval
    var fullSnapshotTargetSize: CGSize
    var windowThumbnailTargetSize: CGSize
    var maxWindowThumbnailsPerWorkspace: Int
    var closeAfterWorkspaceSwitch: Bool
    var showMenuBarIcon: Bool
    var refreshFocusedWorkspaceOnly: Bool
    var debugMode: Bool

    static let `default` = AppConfig(
        refreshIntervalSeconds: 3,
        fullSnapshotStaleSeconds: 15,
        windowThumbnailsStaleSeconds: 30,
        fullSnapshotTargetSize: CGSize(width: 480, height: 300),
        windowThumbnailTargetSize: CGSize(width: 240, height: 160),
        maxWindowThumbnailsPerWorkspace: 4,
        closeAfterWorkspaceSwitch: true,
        showMenuBarIcon: true,
        refreshFocusedWorkspaceOnly: true,
        debugMode: false
    )
}
