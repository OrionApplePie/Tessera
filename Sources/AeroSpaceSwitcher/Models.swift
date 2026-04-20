import CoreGraphics
import Foundation

struct Workspace: Identifiable, Hashable {
    let id: String
    let isFocused: Bool
}

struct AeroSpaceWindow: Hashable {
    let workspace: String
    let appName: String
    let title: String
}

struct WorkspaceTileModel: Identifiable {
    let id: String
    let isFocused: Bool
    var fullSnapshot: CGImage?
    var previews: [WindowPreviewModel]
    var previewSource: WorkspacePreviewSource
    var isPreviewStale: Bool
}

struct WindowPreviewModel: Identifiable {
    let id: String
    let appName: String
    let title: String
    var thumbnail: CGImage?

    var fallbackTitle: String {
        if !title.isEmpty {
            return title
        }

        return "<untitled>"
    }
}

struct WindowPreviewRequest {
    let id: String
    let workspaceID: String
    let window: AeroSpaceWindow
}

enum WorkspacePreviewSource {
    case full
    case composite
    case fallback
}
