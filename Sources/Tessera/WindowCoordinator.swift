import AppKit
import Combine
import CoreGraphics
import Foundation

/// Keeps the switchable window list and its thumbnails fresh, and performs activation.
@MainActor
final class WindowCoordinator: ObservableObject {
  /// Tiles grouped by display, in the order the overlay draws them.
  @Published private(set) var sections: [WindowTileSection] = []
  @Published private(set) var isRefreshPaused = false

  /// Every tile in draw order. Activation, the number keys and the arrow keys all
  /// address tiles by this flat index, so sections stay purely a layout concern.
  var tiles: [WindowTileModel] {
    sections.flatMap(\.tiles)
  }

  private let config: AppConfig
  private let logger: AppLogger
  private let windowListService: WindowListService
  private let thumbnailService: WindowThumbnailService
  private let activator: WindowActivator
  private let previewCache: WindowPreviewCache
  private var isRunning = false
  private var refreshTask: Task<Void, Never>?
  private var spaceTracker = SpaceTracker()
  private var orderRegistry = WindowOrderRegistry()
  private var isListHeld = false
  private var lastForeignFrontmostProcessID: pid_t?
  private var activationVerifier = ActivationVerifier()
  private let learnedWindows: LearnedWindowStore
  private var activeSpaceObserver: (any NSObjectProtocol)?

  init(
    config: AppConfig = .default,
    windowListService: WindowListService? = nil,
    thumbnailService: WindowThumbnailService? = nil,
    activator: WindowActivator? = nil,
    previewCache: WindowPreviewCache? = nil
  ) {
    self.config = config
    self.logger = AppLogger(debugMode: config.debugMode, category: .preview)

    let store = LearnedWindowStore(debugMode: config.debugMode)
    self.learnedWindows = store
    self.windowListService =
      windowListService ?? WindowListService(config: config, learnedWindows: store)
    self.thumbnailService = thumbnailService ?? WindowThumbnailService(config: config)
    self.activator = activator ?? WindowActivator(config: config)
    self.previewCache = previewCache ?? WindowPreviewCache(config: config)
  }

  var isAccessibilityTrusted: Bool {
    activator.isAccessibilityTrusted
  }

  func start() {
    guard !isRunning else {
      return
    }

    isRunning = true
    logger.info("Starting window coordinator")
    observeActiveSpaceChanges()

    Task { @MainActor [weak self] in
      await self?.refreshNow()
      self?.startRefreshLoop()
    }
  }

  func stop() {
    isRunning = false
    refreshTask?.cancel()
    refreshTask = nil

    if let activeSpaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
      self.activeSpaceObserver = nil
    }
    previewCache.clear()
    sections = []
    logger.info("Stopped window coordinator and cleared in-memory preview cache")
  }

  func pauseRefresh() {
    isRefreshPaused = true
    logger.info("Preview refresh paused")
  }

  func resumeRefresh() {
    isRefreshPaused = false
    logger.info("Preview refresh resumed")

    if isRunning {
      Task { @MainActor [weak self] in
        await self?.refreshNow()
      }
    }
  }

  func requestAccessibilityPermission() {
    logger.info("Requesting Accessibility permission")
    activator.requestAccessibilityPermission()
  }

  /// Freezes the list while the overlay is on screen.
  ///
  /// A refresh re-sorts, and a re-sort under an open overlay moves the tiles the
  /// user is looking at — a window whose title changed, a Space that just became
  /// active, a thumbnail that arrived late. The switcher should show a snapshot.
  /// It also stops the captures, which are pure waste for those few seconds.
  ///
  /// Kept apart from `pauseRefresh()`, which is the user's own choice from the
  /// menu bar and must survive the overlay opening and closing.
  func holdList() {
    isListHeld = true
    logger.debug("Holding the window list while the overlay is open")
  }

  func releaseList() {
    guard isListHeld else {
      return
    }

    isListHeld = false
    logger.debug("Released the window list")

    guard isRunning else {
      return
    }

    Task { @MainActor [weak self] in
      await self?.refreshNow()
    }
  }

  func refreshNow() async {
    guard !isListHeld else {
      logger.debug("Skipping a refresh; the overlay is holding the list")
      return
    }

    logger.debug("Refreshing window model now")

    let snapshot: WindowSnapshot
    do {
      snapshot = try await windowListService.snapshot()
    } catch {
      logger.error("Failed to list windows: \(error)")
      return
    }

    // Learn before ordering: the lesson is what is on screen across every window,
    // and the cap below would hide part of it.
    updateSpaceTracker(with: snapshot.windows)
    judgeRecentActivations(against: snapshot.windows)

    // In a stable order a Space switch must not reshuffle anything — unless Spaces
    // are what the overlay groups by, where dropping the rank would let sections
    // interleave.
    let ranksSort =
      config.windowOrder != .stable || config.overlayGrouping.contains(.spaces)
    let windows = WindowListService.ordered(
      snapshot.windows,
      displayOrder: snapshot.displayOrder,
      spaceRanks: ranksSort ? spaceRanks(for: snapshot.windows) : [:],
      sequence: orderRegistry.sequence(for: snapshot.windows),
      order: config.windowOrder,
      limit: config.maxWindows
    )

    let frontmostWindowID = FrontmostWindow.identify(
      processID: frontmostApplicationProcessID(),
      among: Set(windows.map(\.id)),
      frontToBack: FrontmostWindow.onScreenFrontToBack()
    )
    previewCache.retain(windowIDs: windows.map(\.id))

    let icons = applicationIcons(for: windows)

    var model = windows.map { window in
      WindowTileModel(
        id: window.id,
        appName: window.appName,
        title: window.title,
        processID: window.processID,
        isActive: window.id == frontmostWindowID,
        isMinimized: window.isMinimized,
        displayID: window.displayID,
        spaceIndex: spaceTracker.spaceIndex(of: window.id, on: window.displayID),
        icon: icons[window.processID],
        thumbnail: nil,
        isThumbnailStale: false
      )
    }

    applyCache(to: &model)
    publish(model, displayNames: snapshot.displayNames)

    // A minimized window has no surface: the capture would not fail, it would
    // never answer. Whatever was cached before it went to the Dock is kept.
    let capturable = windows.filter { !$0.isMinimized }.map(\.id)
    let thumbnails = await thumbnailService.thumbnails(for: capturable)
    guard !thumbnails.isEmpty else {
      if !windows.isEmpty {
        logger.warning("No window thumbnails available; UI will use fallback previews")
      }
      return
    }

    previewCache.storeThumbnails(thumbnails)
    applyCache(to: &model)
    publish(model, displayNames: snapshot.displayNames)
  }

  /// Every window on screen on one display shares that display's active Space.
  private func updateSpaceTracker(with windows: [WindowInfo]) {
    for displayID in Set(windows.map(\.displayID)) {
      let onScreen = windows.filter { $0.displayID == displayID && $0.isOnScreen }
      spaceTracker.observe(onScreen: Set(onScreen.map(\.id)), on: displayID)
    }

    spaceTracker.retain(windowIDs: Set(windows.map(\.id)))

    let learned = Set(windows.map(\.displayID))
      .sorted()
      .map { "\($0):\(spaceTracker.knownSpaceCount(on: $0))" }
      .joined(separator: " ")
    logger.debug("Spaces learned so far (display:count) \(learned)")
  }

  /// A window that was asked to come forward and did not is a leftover of an
  /// application that keeps its window object after closing it. Nothing about the
  /// window says so; only the outcome does.
  private func judgeRecentActivations(against windows: [WindowInfo]) {
    let outcomes = activationVerifier.evaluate(
      onScreen: Set(windows.filter(\.isOnScreen).map(\.id)),
      existing: Set(windows.map(\.id))
    )

    for outcome in outcomes {
      if outcome.cameForward {
        learnedWindows.forget(outcome.signature)
      } else {
        learnedWindows.learn(outcome.signature)
      }
    }
  }

  /// Sort rank per window: the Space being looked at first, then the rest in the
  /// order they were learned. Windows on an unknown Space get no rank and sort last.
  private func spaceRanks(for windows: [WindowInfo]) -> [CGWindowID: Int] {
    var ranks: [CGWindowID: Int] = [:]

    for displayID in Set(windows.map(\.displayID)) {
      let onDisplay = windows.filter { $0.displayID == displayID }
      let activeSpace =
        onDisplay
        .first { $0.isOnScreen }
        .flatMap { spaceTracker.spaceIndex(of: $0.id, on: displayID) }

      for window in onDisplay {
        guard let index = spaceTracker.spaceIndex(of: window.id, on: displayID) else {
          continue
        }

        ranks[window.id] = index == activeSpace ? -1 : index
      }
    }

    return ranks
  }

  /// Switching Spaces is the moment the window list changes most, and the moment
  /// there is something new to learn about which windows live together.
  private func observeActiveSpaceChanges() {
    guard activeSpaceObserver == nil else {
      return
    }

    activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // Registered against the main queue, so the hop is a formality rather than a
      // thread change.
      MainActor.assumeIsolated {
        guard let self, self.isRunning else {
          return
        }

        self.logger.debug("Active Space changed; refreshing")
        Task { @MainActor [weak self] in
          await self?.refreshNow()
        }
      }
    }
  }

  func activateWindow(id windowID: CGWindowID) {
    guard let tile = tiles.first(where: { $0.id == windowID }) else {
      logger.warning("Activation requested for a window that is no longer listed")
      return
    }

    do {
      let result = try activator.activate(tile)
      logger.info("Activated window")

      // Only an activation that could aim at this window says anything about it.
      // Accessibility does not list every window — Finder's are missing — and a
      // raise that hit something else would condemn a window that never got asked.
      switch result {
      case .raisedTheWindow:
        activationVerifier.recordActivation(
          of: windowID,
          signature: WindowSignature(applicationName: tile.appName, title: tile.title)
        )
      case .couldNotAimAtTheWindow:
        logger.info(
          "Accessibility could not aim at this window, so its outcome teaches nothing")
      }
    } catch {
      logger.error("Failed to activate window: \(error)")
    }

    Task { @MainActor [weak self] in
      await self?.refreshNow()
    }
  }

  /// Activation by position, for the overlay's number-key shortcuts.
  func activateWindow(at index: Int) {
    guard tiles.indices.contains(index) else {
      return
    }

    activateWindow(id: tiles[index].id)
  }

  private func startRefreshLoop() {
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

        guard !self.isRefreshPaused, !self.isListHeld else {
          continue
        }

        await self.refreshNow()
      }
    }
  }
}

// MARK: - Tiles

extension WindowCoordinator {
  private func publish(
    _ tiles: [WindowTileModel],
    displayNames: [CGDirectDisplayID: String]
  ) {
    sections = WindowTileSection.sections(
      from: tiles,
      displayNames: displayNames,
      grouping: config.overlayGrouping
    )
  }

  /// The application in front, not counting this one.
  ///
  /// Showing the overlay activates Tessera, so a refresh while it is open finds
  /// Tessera frontmost and would mark no window at all — the highlight on the
  /// window the user came from would simply go out a second later. The last
  /// application that was in front before that is the answer worth keeping.
  private func frontmostApplicationProcessID() -> pid_t? {
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier

    if let frontmost, frontmost != ProcessInfo.processInfo.processIdentifier {
      lastForeignFrontmostProcessID = frontmost
    }

    return lastForeignFrontmostProcessID
  }

  /// One icon per application rather than per window, since every window of an
  /// application shows the same one.
  private func applicationIcons(for windows: [WindowInfo]) -> [pid_t: NSImage] {
    let entries = Set(windows.map(\.processID)).compactMap { processID in
      NSRunningApplication(processIdentifier: processID)?.icon.map { (processID, $0) }
    }

    return Dictionary(uniqueKeysWithValues: entries)
  }

  private func applyCache(to tiles: inout [WindowTileModel]) {
    for index in tiles.indices {
      let windowID = tiles[index].id
      tiles[index].thumbnail = previewCache.thumbnail(for: windowID)
      tiles[index].isThumbnailStale = previewCache.isStale(windowID: windowID)
    }
  }
}
