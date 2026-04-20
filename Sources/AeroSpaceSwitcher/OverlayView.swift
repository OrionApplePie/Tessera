import SwiftUI

struct OverlayView: View {
    @ObservedObject var previewCoordinator: PreviewCoordinator
    let onSelect: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(previewCoordinator.tiles) { workspace in
                WorkspaceTileButton(workspace: workspace) {
                    onSelect(workspace.id)
                }
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onExitCommand(perform: onClose)
    }
}

private struct WorkspaceTileButton: View {
    let workspace: WorkspaceTileModel
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text(workspace.id)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(workspace.isFocused ? Color.black : Color.white)

                    Spacer(minLength: 0)

                    if workspace.isFocused {
                        Circle()
                            .fill(Color.black.opacity(0.72))
                            .frame(width: 10, height: 10)
                    }
                }
                .frame(height: 36)

                WorkspacePreviewContent(workspace: workspace)
            }
            .padding(14)
            .frame(width: 190, height: 198)
            .background(tileBackground)
            .overlay(tileBorder)
        }
        .buttonStyle(.plain)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(workspace.isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.1))
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(workspace.isFocused ? Color.white.opacity(0.88) : Color.white.opacity(0.16), lineWidth: 1)
    }
}

private struct WorkspacePreviewContent: View {
    let workspace: WorkspaceTileModel

    var body: some View {
        if let fullSnapshot = workspace.fullSnapshot {
            FullSnapshotPreview(image: fullSnapshot, isStale: workspace.isPreviewStale)
        } else {
            WindowPreviewGrid(previews: workspace.previews, isStale: workspace.isPreviewStale)
        }
    }
}

private struct FullSnapshotPreview: View {
    let image: CGImage
    let isStale: Bool

    var body: some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .scaledToFill()
            .frame(height: 117)
            .opacity(isStale ? 0.72 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

private struct WindowPreviewGrid: View {
    let previews: [WindowPreviewModel]
    let isStale: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    var body: some View {
        if previews.isEmpty {
            EmptyWorkspacePreview()
        } else {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(previews.prefix(4)) { preview in
                    WindowPreviewCell(preview: preview)
                }
            }
            .frame(height: 117, alignment: .top)
            .opacity(isStale ? 0.72 : 1.0)
        }
    }
}

private struct WindowPreviewCell: View {
    let preview: WindowPreviewModel

    var body: some View {
        ZStack {
            if let thumbnail = preview.thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.appName.isEmpty ? "App" : preview.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(preview.fallbackTitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(7)
                .background(Color.white.opacity(0.08))
            }
        }
        .frame(height: 55)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct EmptyWorkspacePreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                Text("Empty")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .frame(height: 117)
    }
}
