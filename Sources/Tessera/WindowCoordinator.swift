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
  private let menuActivator: WindowMenuActivator
  private let previewCache: WindowPreviewCache
  private var isRunning = false
  private var refreshTask: Task<Void, Never>?
  private var spaceTracker = SpaceTracker()
  private let spaceQuery: SpaceQuery
  /// What the window server said, when it was asked and answered.
  private var exactSpaceIndices: [CGWindowID: Int] = [:]
  /// How many Spaces each display has, so the empty ones still get a place on the
  /// map, and which of them is showing now.
  private var spaceCounts: [CGDirectDisplayID: Int] = [:]
  private var currentSpaces: [CGDirectDisplayID: Int] = [:]
  /// What each group is called: a desktop by its number among desktops, a
  /// fullscreen Space by the application filling it — the way Mission Control
  /// names them.
  private var spaceNames: [WindowSectionID: String] = [:]
  private var fullscreenSpaces: Set<WindowSectionID> = []
  private var spaceOrder: [CGDirectDisplayID: [SpaceQuery.Space]] = [:]
  private let wallpaper = DesktopWallpaper()
  private var orderRegistry = WindowOrderRegistry()
  private var isListHeld = false
  private var pendingRaise: WindowTileModel?
  private var pendingRaiseDeadline: Task<Void, Never>?
  /// Set the first time a tile is dragged. The arrangement then outranks the
  /// configured order for the rest of the session, because an order someone made
  /// by hand is not one a sort should undo.
  private var isArrangedByHand = false
  private var lastForeignFrontmostProcessID: pid_t?
  private var activationVerifier: ActivationVerifier
  private let learnedWindows: LearnedWindowStore
  private var workspaceObservers: [any NSObjectProtocol] = []

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
    self.spaceQuery = SpaceQuery(
      enabled: config.usesPrivateSpaceAPI, debugMode: config.debugMode)
    self.menuActivator = WindowMenuActivator(
      timeout: config.unresponsiveAfterSeconds, debugMode: config.debugMode)
    self.activationVerifier = ActivationVerifier(grace: config.activationSettleSeconds)
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
    clearPendingRaise()

    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers = []
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

  /// Recomputes which window is in front, without touching the list or the
  /// thumbnails.
  ///
  /// The mark is otherwise as old as the last background refresh — up to a refresh
  /// interval — and the overlay opening is exactly the moment it must be right: it
  /// says where you are, and it is where the keyboard highlight starts.
  func refreshActiveWindow() {
    let frontmostWindowID = FrontmostWindow.identify(
      processID: frontmostApplicationProcessID(),
      among: Set(tiles.map(\.id)),
      frontToBack: FrontmostWindow.onScreenFrontToBack()
    )

    sections = sections.map { section in
      var section = section
      section.tiles = section.tiles.map { tile in
        var tile = tile
        tile.isActive = tile.id == frontmostWindowID
        return tile
      }
      return section
    }
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

  /// - Parameters:
  ///   - force: Refresh even while the overlay is holding the list, for a change
  ///     the user made themselves and must see.
  ///   - capturingThumbnails: Off for a refresh that has to be quick — the list is
  ///     what is wrong, and the previews already in the cache are good enough to
  ///     show while a later refresh replaces them.
  func refreshNow(force: Bool = false, capturingThumbnails: Bool = true) async {
    guard !isListHeld || force else {
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
    updateExactSpaces(with: snapshot.windows)
    judgeRecentActivations(against: snapshot.windows)
    forgetPendingRaiseIfItArrived(snapshot.windows)

    // In a stable order a Space switch must not reshuffle anything — unless Spaces
    // are what the overlay groups by, where dropping the rank would let sections
    // interleave.
    let effectiveOrder = isArrangedByHand ? WindowOrder.stable : config.windowOrder
    let ranksSort =
      effectiveOrder != .stable || config.overlayGrouping.contains(.spaces)
    let windows = WindowListService.ordered(
      snapshot.windows,
      displayOrder: snapshot.displayOrder,
      spaceRanks: ranksSort ? spaceRanks(for: snapshot.windows) : [:],
      sequence: orderRegistry.sequence(for: snapshot.windows),
      order: isArrangedByHand ? .stable : config.windowOrder,
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
        spaceIndex: spaceIndex(of: window.id, on: window.displayID),
        icon: icons[window.processID],
        thumbnail: nil,
        isThumbnailStale: false
      )
    }

    applyCache(to: &model)
    publish(model, displayNames: snapshot.displayNames)

    guard capturingThumbnails else {
      return
    }

    await captureThumbnails(for: windows, into: model, displayNames: snapshot.displayNames)
  }

  /// A minimized window has no surface: the capture would not fail, it would never
  /// answer. Whatever was cached before it went to the Dock is kept.
  private func captureThumbnails(
    for windows: [WindowInfo],
    into model: [WindowTileModel],
    displayNames: [CGDirectDisplayID: String]
  ) async {
    var model = model
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
    publish(model, displayNames: displayNames)
  }

  /// Every window on screen on one display shares that display's active Space.
  func activateWindow(id windowID: CGWindowID) {
    guard let tile = tiles.first(where: { $0.id == windowID }) else {
      logger.warning("Activation requested for a window that is no longer listed")
      return
    }

    // Whatever was waiting to be judged is dropped: a window asked for a moment ago
    // is allowed to be off screen once something else has been asked for.
    activationVerifier.forgetPending()

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
        raiseOnceTheSpaceHasSwitched(tile)
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

// MARK: - Raising

/// Bringing one window forward, by whichever of the three ways answers.
///
/// Accessibility first, because it aims at a window without side effects, and the
/// application's own Window menu when that fails, because it is the only public
/// list that names a window on another Space.
extension WindowCoordinator {
  /// Brings a window forward without taking the keyboard from the overlay.
  ///
  /// Returns whether the window could be aimed at, so that stepping past a window
  /// nothing can raise is a step and not a jump to somewhere unexpected.
  @discardableResult
  func raiseWindow(id windowID: CGWindowID) -> Bool {
    guard let tile = tiles.first(where: { $0.id == windowID }) else {
      return false
    }

    activationVerifier.forgetPending()

    do {
      return try activator.raiseWithoutActivating(tile) == .raisedTheWindow
    } catch {
      logger.error("Failed to raise \(tile.displayAppName): \(error)")
      return false
    }
  }

  /// Tries the raise again once the Space has had time to change.
  ///
  /// Accessibility lists no windows of an application whose windows are all on
  /// another Space, so activating one of several — three Chrome windows, two Word
  /// documents — could only bring the application forward and let it choose. Once
  /// the switch has happened those windows are on this Space, Accessibility can see
  /// them, and the one that was asked for can be raised after all.
  private func raiseOnceTheSpaceHasSwitched(_ tile: WindowTileModel) {
    // The Window menu is asked first, because it answers the case that brought us
    // here — a window Accessibility cannot see. But only of an application that is
    // already frontmost: pressing an item of one that is not returns success and
    // does nothing, measured, which is how a switch could report that it had worked
    // and leave the window where it was. Activation has only just been asked for,
    // so usually it is not frontmost yet, and the press waits below for the system
    // to say that it is.
    if isFrontmost(tile), raiseThroughWindowMenu(tile) {
      return
    }

    // Otherwise the window is remembered, and asked for again when the system says
    // something has changed. The wait below is not a poll: it is only the point at
    // which waiting stops.
    pendingRaise = tile
    pendingRaiseDeadline?.cancel()
    pendingRaiseDeadline = Task { @MainActor [weak self] in
      guard let settle = self?.config.activationSettleSeconds else {
        return
      }

      try? await Task.sleep(for: .seconds(settle))

      guard let self, self.pendingRaise?.id == tile.id else {
        return
      }

      self.giveUpOnPendingRaise(tile)
    }
  }

  /// Asks again for the window that could not be reached, now that the system has
  /// announced a change. Called for a Space switch and for an application coming
  /// forward, which are the two things that turn an unreachable window into a
  /// reachable one.
  private func attemptPendingRaise() {
    guard let tile = pendingRaise, isFrontmost(tile) else {
      return
    }

    if (try? activator.raiseWithoutActivating(tile)) == .raisedTheWindow {
      logger.info("Raised the window once the system had settled")
      clearPendingRaise()
      return
    }

    // Now that the application is frontmost its menu will act, which it would not
    // have done at the moment the window was chosen.
    if raiseThroughWindowMenu(tile) {
      clearPendingRaise()
    }
  }

  private func isFrontmost(_ tile: WindowTileModel) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == tile.processID
  }

  /// The last try, for when nothing was announced at all — the application was
  /// already frontmost and no Space had to change — and the report when there is
  /// nothing left to try.
  ///
  /// Accessibility only. The Window menu was asked at the start, and asking it
  /// again a second and a half later means pressing a menu item in an application
  /// the person may well be using by then: they see its menu open by itself, for a
  /// window that has usually arrived already.
  private func giveUpOnPendingRaise(_ tile: WindowTileModel) {
    if (try? activator.raiseWithoutActivating(tile)) == .raisedTheWindow {
      logger.info("Raised the window when the wait ran out")
    } else {
      logger.info("The window could not be raised by any means")
    }

    clearPendingRaise()
  }

  /// Drops the pending raise once the window is on screen, however it got there.
  ///
  /// Without this, a window the person reached themselves — by switching Spaces, or
  /// by clicking it — would still be chased when the wait ran out, in an
  /// application they had moved on to.
  private func forgetPendingRaiseIfItArrived(_ windows: [WindowInfo]) {
    guard let pending = pendingRaise,
      windows.contains(where: { $0.id == pending.id && $0.isOnScreen })
    else {
      return
    }

    logger.debug("The window arrived on its own; nothing left to ask for")
    clearPendingRaise()
  }

  private func clearPendingRaise() {
    pendingRaise = nil
    pendingRaiseDeadline?.cancel()
    pendingRaiseDeadline = nil
  }

  /// Presses the window's entry in its application's own Window menu, which is the
  /// only public list that names windows on other Spaces — and so the only way to
  /// reach one fullscreen window from another.
  private func raiseThroughWindowMenu(_ tile: WindowTileModel) -> Bool {
    menuActivator.raiseWindow(titled: tile.title, processID: tile.processID)
  }

}

// MARK: - Learning

extension WindowCoordinator {
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
}

// MARK: - Spaces

extension WindowCoordinator {
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
  /// Sort rank per window: the Space being looked at first, then the rest in the
  /// order they were learned. Windows on an unknown Space get no rank and sort last.
  /// The Space a window is on: asked, when the window server will say, and inferred
  /// otherwise. One is exact and one is a good guess, and the rest of the code does
  /// not need to know which it got.
  private func spaceIndex(of windowID: CGWindowID, on displayID: CGDirectDisplayID) -> Int? {
    exactSpaceIndices[windowID] ?? spaceTracker.spaceIndex(of: windowID, on: displayID)
  }

  /// Turns the window server's Space identifiers into the small per-display numbers
  /// the overlay groups by. Ordered by identifier, which is the order the Spaces
  /// were made in, so a heading does not move about between refreshes.
  private func updateExactSpaces(with windows: [WindowInfo]) {
    guard spaceQuery.isAvailable else {
      exactSpaceIndices = [:]
      return
    }

    let spaces = spaceQuery.spaces(of: windows.map(\.id))

    // Numbered the way the system numbers them: the order Mission Control shows and
    // the ⌃1…⌃N shortcuts count in, which is the order the window server keeps them
    // in. Numbering by identifier would be our own order and match nothing anyone
    // sees.
    let systemOrder = spaceQuery.orderedSpaces()
    let active = spaceQuery.activeSpace()
    spaceOrder = systemOrder
    var indices: [CGWindowID: Int] = [:]
    var counts: [CGDirectDisplayID: Int] = [:]
    var current: [CGDirectDisplayID: Int] = [:]
    var names: [WindowSectionID: String] = [:]
    var fullscreen: Set<WindowSectionID> = []

    for displayID in Set(windows.map(\.displayID)).union(systemOrder.keys) {
      let onDisplay = windows.filter { $0.displayID == displayID }
      let present = Set(onDisplay.compactMap { spaces[$0.id] })
      // Every Space the display has, in the system's order — not only the ones with
      // something in them, so the numbering matches what Mission Control shows.
      let ordered =
        systemOrder[displayID]
        ?? present.sorted().map { SpaceQuery.Space(id: $0, isFullscreen: false) }

      counts[displayID] = ordered.count
      current[displayID] = active.flatMap { space in ordered.firstIndex { $0.id == space } }

      for window in onDisplay {
        guard let space = spaces[window.id],
          let rank = ordered.firstIndex(where: { $0.id == space })
        else {
          continue
        }

        indices[window.id] = rank
      }

      names.merge(
        SpaceQuery.names(for: ordered, on: displayID, windows: onDisplay, spaces: spaces)
      ) { first, _ in first }

      for (index, space) in ordered.enumerated() where space.isFullscreen {
        fullscreen.insert(WindowSectionID(displayID: displayID, spaceIndex: index))
      }
    }

    spaceCounts = counts
    currentSpaces = current.compactMapValues { $0 }
    spaceNames = names
    fullscreenSpaces = fullscreen

    logger.debug("Spaces from the window server: \(indices.count) of \(windows.count) windows")
    exactSpaceIndices = indices
  }

  private func spaceRanks(for windows: [WindowInfo]) -> [CGWindowID: Int] {
    var ranks: [CGWindowID: Int] = [:]

    for displayID in Set(windows.map(\.displayID)) {
      let onDisplay = windows.filter { $0.displayID == displayID }
      let activeSpace =
        onDisplay
        .first { $0.isOnScreen }
        .flatMap { spaceIndex(of: $0.id, on: displayID) }

      for window in onDisplay {
        guard let index = spaceIndex(of: window.id, on: displayID) else {
          continue
        }

        ranks[window.id] = index == activeSpace ? -1 : index
      }
    }

    return ranks
  }
  /// The moments the window list changes most, and the moment there is something
  /// new to learn about which windows live together.
  ///
  /// There is no public notification for a window opening — only for an
  /// application launching, quitting or coming forward — so this catches the
  /// common cases and the periodic refresh catches the rest.
  private func observeActiveSpaceChanges() {
    guard workspaceObservers.isEmpty else {
      return
    }

    let names: [Notification.Name] = [
      NSWorkspace.activeSpaceDidChangeNotification,
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ]

    workspaceObservers = names.map { name in
      observeWorkspace(name) { coordinator in
        coordinator.attemptPendingRaise()
        coordinator.logger.debug("Workspace changed; refreshing")

        Task { @MainActor [weak coordinator] in
          await coordinator?.refreshNow()
        }
      }
    }

    // An application coming forward asks for nothing else: it happens on every
    // switch, and rebuilding the list each time would cost more than it tells.
    workspaceObservers.append(
      observeWorkspace(NSWorkspace.didActivateApplicationNotification) { coordinator in
        coordinator.attemptPendingRaise()
      })
  }

  private func observeWorkspace(
    _ name: Notification.Name,
    _ body: @escaping @MainActor (WindowCoordinator) -> Void
  ) -> NSObjectProtocol {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // Registered against the main queue, so the hop is a formality rather than a
      // thread change.
      MainActor.assumeIsolated {
        guard let self, self.isRunning else {
          return
        }

        body(self)
      }
    }
  }
}

// MARK: - Closing

extension WindowCoordinator {
  /// Closes what the highlight is on, as the configuration understands closing.
  ///
  /// Quitting is the default because an application that keeps running with its
  /// window closed is how a leftover window is made — one this switcher cannot
  /// tell from a window on another Space.
  func closeWindow(id windowID: CGWindowID) {
    guard let tile = tiles.first(where: { $0.id == windowID }) else {
      logger.warning("Close requested for a window that is no longer listed")
      return
    }

    do {
      switch config.closeAction {
      case .quitApplication:
        try activator.quitApplication(tile)
        logger.info("Asked \(tile.displayAppName) to quit")
      case .closeWindow:
        try activator.close(tile)
        logger.info("Closed a window of \(tile.displayAppName)")
      }
    } catch {
      logger.error("Failed to close \(tile.displayAppName): \(error)")
    }

    // The window does not close the instant it is asked to — an application gets to
    // finish what it was doing, and one that is quitting may take a second. Taking
    // the tile away now is the honest reading of what was asked for; if the
    // application refuses, the next refresh puts it back.
    sections = sections.compactMap { section in
      var section = section
      section.tiles.removeAll { $0.id == windowID }
      return section.tiles.isEmpty ? nil : section
    }
    logger.debug("Took the tile away at once; \(tiles.count) left")
  }
}

// MARK: - Arranging

extension WindowCoordinator {
  /// Swaps the tile at one place in the list with the tile at another.
  ///
  /// Refused across a group boundary, so a thumbnail never lands under another
  /// display's heading. Returns whether anything moved, so the caller knows
  /// whether to follow it with the highlight.
  @discardableResult
  func swapTiles(at index: Int, with target: Int) -> Bool {
    guard let swapped = WindowTileSection.swapping(index, target, in: sections) else {
      return false
    }

    sections = swapped
    orderRegistry.arrange(tiles.map(\.id))
    isArrangedByHand = true
    logger.info("Arranged tiles by hand")
    return true
  }

  /// Moves a tile in front of another, within the display they share.
  ///
  /// Purely visual: the window itself is not moved, and could not be moved between
  /// displays without changing its frame, which is not what an arrangement of
  /// thumbnails is for. A tile dropped on another display's tile is refused rather
  /// than silently relocated.
  func moveTile(_ windowID: CGWindowID, before targetID: CGWindowID) {
    guard windowID != targetID,
      let moving = tiles.first(where: { $0.id == windowID }),
      let target = tiles.first(where: { $0.id == targetID }),
      moving.displayID == target.displayID,
      let sectionIndex = sections.firstIndex(where: { section in
        section.tiles.contains { $0.id == windowID } && section.tiles.contains { $0.id == targetID }
      })
    else {
      return
    }

    var arranged = sections[sectionIndex].tiles
    guard let from = arranged.firstIndex(where: { $0.id == windowID }) else {
      return
    }

    let tile = arranged.remove(at: from)
    let to = arranged.firstIndex { $0.id == targetID } ?? arranged.count
    arranged.insert(tile, at: to)
    sections[sectionIndex].tiles = arranged

    orderRegistry.arrange(tiles.map(\.id))
    isArrangedByHand = true
    logger.info("Arranged tiles by hand")
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
      grouping: config.overlayGrouping,
      spaceCounts: spaceCounts,
      currentSpaces: currentSpaces,
      spaceNames: spaceNames,
      fullscreenSpaces: fullscreenSpaces
    )
  }

  /// Shows the Space a group stands for. Choosing an empty one is the only way onto
  /// an empty desktop: there is no window there to activate.
  func focusSpace(at index: Int, on displayID: CGDirectDisplayID) {
    guard let ordered = spaceOrder[displayID], ordered.indices.contains(index) else {
      return
    }

    logger.info("Switching to a Space chosen from the overlay")
    spaceQuery.focus(space: ordered[index].id, on: displayID)
  }

  /// The desktop picture of a display, for drawing a Space with nothing on it.
  func desktopImage(for displayID: CGDirectDisplayID, fitting size: CGSize) -> CGImage? {
    wallpaper.image(for: displayID, fitting: size)
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
