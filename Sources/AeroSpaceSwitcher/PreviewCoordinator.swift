import Combine
import Foundation

@MainActor
final class PreviewCoordinator: ObservableObject {
    @Published private(set) var tiles: [WorkspaceTileModel]
    @Published private(set) var isRefreshPaused = false

    private let config: AppConfig
    private let client: AeroSpaceClient
    private let thumbnailService: WindowThumbnailService
    private let screenshotService: WorkspaceScreenshotService
    private let previewCache: WorkspacePreviewCache
    private var isRunning = false
    private var refreshTask: Task<Void, Never>?

    init(
        client: AeroSpaceClient,
        config: AppConfig = .default,
        thumbnailService: WindowThumbnailService? = nil,
        screenshotService: WorkspaceScreenshotService? = nil,
        previewCache: WorkspacePreviewCache? = nil
    ) {
        self.config = config
        self.client = client
        self.thumbnailService = thumbnailService ?? WindowThumbnailService(config: config)
        self.screenshotService = screenshotService ?? WorkspaceScreenshotService(config: config)
        self.previewCache = previewCache ?? WorkspacePreviewCache(config: config)
        self.tiles = Self.placeholderTiles()
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true

        Task { @MainActor [weak self] in
            await self?.refreshNow()
            self?.startSnapshotRefreshLoop()
        }
    }

    func stop() {
        isRunning = false
        refreshTask?.cancel()
        refreshTask = nil
        previewCache.clear()
        tiles = Self.placeholderTiles()
    }

    func pauseRefresh() {
        isRefreshPaused = true
    }

    func resumeRefresh() {
        isRefreshPaused = false

        if isRunning {
            Task { @MainActor [weak self] in
                await self?.refreshFocusedWorkspaceSnapshot()
            }
        }
    }

    func refreshNow() async {
        await refreshWorkspaceModel()
        await refreshFocusedWorkspaceSnapshot()
    }

    func switchWorkspace(_ workspaceID: String) {
        do {
            try client.switchWorkspace(workspaceID)
        } catch {
            fputs("Error: \(error)\n", stderr)
            return
        }

        Task { @MainActor [weak self] in
            await self?.refreshFocusedWorkspaceSnapshot()
        }
    }

    private static func placeholderTiles() -> [WorkspaceTileModel] {
        (1...7).map { number in
            WorkspaceTileModel(
                id: String(number),
                isFocused: false,
                fullSnapshot: nil,
                previews: [],
                previewSource: .fallback,
                isPreviewStale: false
            )
        }
    }

    private func refreshWorkspaceModel() async {
        do {
            let workspaces = try client.listWorkspaces()
            let windows = try client.listWindows()
            var model = makeTiles(workspaces: workspaces, windows: windows)

            previewCache.storeWorkspaceIDs(model.tiles.map(\.id))
            applyCache(to: &model.tiles)
            tiles = model.tiles

            let thumbnails = await thumbnailService.thumbnails(for: model.requests)
            if !thumbnails.isEmpty {
                previewCache.storeWindowThumbnails(
                    thumbnails,
                    groupedByWorkspace: model.requestWorkspaceIDs
                )
                applyCache(to: &model.tiles)
                tiles = model.tiles
            }
        } catch {
            fputs("AeroSpaceSwitcher: failed to refresh workspace previews: \(error)\n", stderr)
        }
    }

    private func makeTiles(
        workspaces: [Workspace],
        windows: [AeroSpaceWindow]
    ) -> (tiles: [WorkspaceTileModel], requests: [WindowPreviewRequest], requestWorkspaceIDs: [String: String]) {
        let focused = Set(workspaces.filter(\.isFocused).map(\.id))
        let windowsByWorkspace = Dictionary(grouping: windows, by: { $0.workspace })
        var requests: [WindowPreviewRequest] = []
        var requestWorkspaceIDs: [String: String] = [:]

        let tiles = (1...7).map { number in
            let workspaceID = String(number)
            let workspaceWindows = Array(
                windowsByWorkspace[workspaceID, default: []].prefix(config.maxWindowThumbnailsPerWorkspace)
            )

            let previews = workspaceWindows.enumerated().map { index, window in
                let previewID = "\(workspaceID)-\(index)-\(window.appName)-\(window.title)"
                requests.append(WindowPreviewRequest(id: previewID, workspaceID: workspaceID, window: window))
                requestWorkspaceIDs[previewID] = workspaceID

                return WindowPreviewModel(
                    id: previewID,
                    appName: window.appName,
                    title: window.title,
                    thumbnail: nil
                )
            }

            return WorkspaceTileModel(
                id: workspaceID,
                isFocused: focused.contains(workspaceID),
                fullSnapshot: nil,
                previews: previews,
                previewSource: .fallback,
                isPreviewStale: false
            )
        }

        return (tiles, requests, requestWorkspaceIDs)
    }

    private func startSnapshotRefreshLoop() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let nanoseconds = UInt64(self.config.refreshIntervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)

                guard !Task.isCancelled else {
                    return
                }

                guard !self.isRefreshPaused else {
                    continue
                }

                if self.config.refreshFocusedWorkspaceOnly {
                    await self.refreshFocusedWorkspaceSnapshot()
                } else {
                    await self.refreshNow()
                }
            }
        }
    }

    private func refreshFocusedWorkspaceSnapshot() async {
        do {
            let focusedIDs = try client.listFocusedWorkspaceIDs()
            guard let focusedWorkspaceID = focusedIDs.first else {
                return
            }

            updateFocusedWorkspace(focusedWorkspaceID)

            var updatedTiles = tiles
            applyCache(to: &updatedTiles)
            tiles = updatedTiles

            guard let snapshot = await screenshotService.captureFocusedWorkspaceSnapshot() else {
                return
            }

            previewCache.storeFullSnapshot(snapshot, for: focusedWorkspaceID)
            updateFocusedWorkspace(focusedWorkspaceID)

            updatedTiles = tiles
            applyCache(to: &updatedTiles)
            tiles = updatedTiles
        } catch {
            fputs("AeroSpaceSwitcher: failed to refresh focused workspace snapshot: \(error)\n", stderr)
        }
    }

    private func updateFocusedWorkspace(_ focusedWorkspaceID: String) {
        tiles = tiles.map { tile in
            WorkspaceTileModel(
                id: tile.id,
                isFocused: tile.id == focusedWorkspaceID,
                fullSnapshot: tile.fullSnapshot,
                previews: tile.previews,
                previewSource: tile.previewSource,
                isPreviewStale: tile.isPreviewStale
            )
        }
    }

    private func applyCache(to tiles: inout [WorkspaceTileModel]) {
        for tileIndex in tiles.indices {
            let workspaceID = tiles[tileIndex].id
            tiles[tileIndex].fullSnapshot = previewCache.fullSnapshot(for: workspaceID)

            for previewIndex in tiles[tileIndex].previews.indices {
                let previewID = tiles[tileIndex].previews[previewIndex].id
                tiles[tileIndex].previews[previewIndex].thumbnail = previewCache.windowThumbnail(
                    for: workspaceID,
                    previewID: previewID
                )
            }

            let previewIDs = tiles[tileIndex].previews.map(\.id)
            let source = previewCache.source(for: workspaceID, previewIDs: previewIDs)
            tiles[tileIndex].previewSource = source
            tiles[tileIndex].isPreviewStale = previewCache.isStale(workspaceID: workspaceID, source: source)
        }
    }
}
