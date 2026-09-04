import AppKit
import Carbon.HIToolbox
import QuartzCore
import SwiftUI

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
  let windowCoordinator: WindowCoordinator
  let config: AppConfig
  private var isPresenting = false
  /// The configured column count, widened when the overlay would otherwise be
  /// taller than the screen it opens on.
  /// How long the panel takes to cross to another display when a step lands there.
  private static let followDuration: TimeInterval = 0.18

  /// The application a step has asked to come forward. Stepping is the one thing
  /// that survives another application activating, because bringing windows forward
  /// while the overlay stays up is the whole of what it does.
  private var steppingActivation: pid_t?
  /// Until when an application coming forward counts as a consequence of a step
  /// rather than as the user leaving.
  private var steppingUntil: ContinuousClock.Instant?

  /// Holds the arrow keys system-wide while the overlay is up, so that stepping
  /// survives the application it just brought forward taking the keyboard.
  private var stepHotkeys: StepHotkeyController?

  /// The last layout measured, and the screen room it was measured for.
  var lastFit: FittedLayout?

  private var activationObserver: NSObjectProtocol?
  var fittedColumns: Int
  /// The geometry the overlay is drawn at, which depends on the screen it opens on.
  var metrics: TileMetrics = .base
  let logger: AppLogger
  let hostingView: TransparentHostingView<OverlayView>
  let selection = OverlaySelection()
  /// The same typing read as Latin letters, so a window named in one alphabet is
  /// found while the keyboard is in the other.
  var latinQuery = ""

  init(windowCoordinator: WindowCoordinator, config: AppConfig = .default) {
    self.windowCoordinator = windowCoordinator
    self.config = config
    self.fittedColumns = config.overlayColumns
    self.logger = AppLogger(debugMode: config.debugMode, category: .overlay)
    self.hostingView = TransparentHostingView(
      rootView: OverlayView(
        metrics: .base,
        windowCoordinator: windowCoordinator,
        selection: OverlaySelection(),
        background: config.overlayBackground,
        columns: config.overlayColumns,
        deck: config.overlayDeck,
        arrangement: config.overlayLayout,
        search: config.overlaySearch,
        rowAlignment: config.overlayRowAlignment,
        dimsStaleThumbnails: config.dimsStaleThumbnails,
        onSelect: { _ in },
        onFocusSpace: { _ in },
        onMove: { _, _ in },
        onClose: {}
      ))

    let panel = OverlayPanel(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 260),
      // Not a non-activating panel, though that sounds like what a switcher wants.
      // Non-activating means the application never becomes active, and macOS routes
      // ordinary keys to whichever application is — so the panel was key inside a
      // process nobody was typing at, and the arrows and Return went to the window
      // behind it. What covers the fullscreen case instead is the handful of keys
      // held as Carbon hotkeys while the overlay is up, which arrive whoever is
      // frontmost.
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    super.init(window: panel)

    panel.delegate = self
    Self.dress(panel)

    // The panel does not hide itself when the application is deactivated, because
    // AppKit remembers such a panel and puts it back the moment the application is
    // activated again — so opening the settings window brought the switcher back
    // with it, unasked, and ordering it out first did not help: it was already out,
    // and that is not what the list is keyed on. Hiding it here instead makes this
    // the only place that decides whether the overlay is on screen.
    panel.hidesOnDeactivate = false

    hostingView.rootView = makeOverlayView()

    // The panel's size is decided here, by the fitting pass, and an `NSHostingView`
    // otherwise takes that decision back: with its default sizing options it pins
    // the window's content size to its own layout through constraints. Those
    // constraints do not settle when the root view is replaced — they arrive a
    // moment later, after the window is already on screen — so the panel appeared
    // at the size asked for and then snapped to the one the view wanted, measured
    // at 26pt shorter. Opening on a screen other than the last one made it obvious,
    // because the size changes with the screen.
    hostingView.sizingOptions = []

    // The content view follows the window instead of being positioned by hand: a
    // frame set manually drifted from the window's own, and SwiftUI then drew its
    // rounded surface to a size the window did not have — the corners fell outside
    // and the panel looked square.
    hostingView.autoresizingMask = [.width, .height]

    // The shape is also cut at the layer, so the window is the rounded rectangle
    // whatever the view inside believes its size to be.
    hostingView.layer?.cornerRadius = TileMetrics.base.surfaceCornerRadius
    hostingView.layer?.cornerCurve = .continuous
    hostingView.layer?.masksToBounds = true

    // The panel is painted at the layer as well as by the view inside it. The
    // fitting pass measures a view that is not in a window and lands a little over
    // what the same view settles at once it is, and with the window no longer
    // resizing itself to the view that difference would show as a transparent band
    // along the edge. Same colour, so where the two meet is not visible.
    hostingView.layer?.backgroundColor = CGColor(
      srgbRed: config.overlayBackground.red,
      green: config.overlayBackground.green,
      blue: config.overlayBackground.blue,
      alpha: config.overlayBackground.alpha
    )

    panel.contentView = hostingView

    connect(panel)
    observeOtherApplications()

    stepHotkeys = StepHotkeyController(
      debugMode: config.debugMode,
      onStep: { [weak self] direction in self?.stepAndActivate(direction) },
      onMove: { [weak self] direction in self?.moveSelection(direction) },
      onDismiss: { [weak self] in self?.hideOverlay() },
      onConfirm: { [weak self] in self?.activateSelection() }
    )
  }

  /// The panel reports what was pressed; this is where each of those becomes an
  /// action on the list.
  private func connect(_ panel: OverlayPanel) {
    panel.onSelectIndex = { [weak self] cell in
      self?.selectCell(cell)
    }
    panel.onMoveSelection = { [weak self] direction in
      self?.moveSelection(direction)
    }
    panel.onSendWindow = { [weak self] direction in
      self?.sendWindow(direction)
    }
    panel.onPlaceWindow = { [weak self] direction in
      self?.place(WindowPlacement.inDirection(direction))
    }
    panel.onFillScreen = { [weak self] in
      self?.place(.full)
    }
    panel.onFullscreen = { [weak self] in
      self?.putFullscreen()
    }
    panel.onMoveTile = { [weak self] direction in
      self?.moveTile(direction)
    }
    panel.onStepAndActivate = { [weak self] direction in
      self?.stepAndActivate(direction)
    }
    panel.closeHotkey = config.closeHotkey
    panel.onCloseWindow = { [weak self] in
      self?.closeSelectedWindow()
    }
    panel.onType = { [weak self] typed, latin, readings in
      self?.type(typed, latin: latin, readings: readings)
    }
    panel.onUntype = { [weak self] in
      self?.untype()
    }
    panel.onClearSearch = { [weak self] in
      self?.selection.query = ""
      self?.latinQuery = ""
    }
    panel.isSearching = { [weak self] in
      self?.selection.query.isEmpty == false
    }
    panel.onCycleWindow = { [weak self] forward in
      self?.cycleWindow(forward: forward)
    }
    panel.onActivateSelection = { [weak self] in
      self?.activateSelection()
    }
    panel.onDismiss = { [weak self] in
      self?.hideOverlay()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showOverlay() {
    guard !isPresenting else {
      return
    }

    isPresenting = true

    // The list is rebuilt before the overlay appears rather than after, so a window
    // opened a moment ago is in it. Thumbnails are not recaptured — that is the
    // slow half — so the cost is one enumeration, and the previews already in the
    // cache carry the tiles until a later refresh replaces them.
    Task { @MainActor [weak self] in
      await self?.windowCoordinator.refreshNow(force: true, capturingThumbnails: false)
      self?.isPresenting = false
      self?.present()
    }
  }

  private func present() {
    guard let window else {
      return
    }

    // A panel that is already on screen is put away before it is placed again.
    // Moving a visible window is a move the eye follows: opening the overlay while
    // it was still up on another display made it slide across, which is the flicker
    // people reported on the display they had just left.
    if window.isVisible {
      window.orderOut(nil)
    }

    // What was typed at the last overlay does not carry over. What was measured
    // does, as long as the map is still the same shape on the same screen: building
    // a dozen layouts to choose a tile size took the better part of a second, and
    // doing it again for a list that has not changed is that second spent twice.
    selection.query = ""
    latinQuery = ""

    // Which window you came from is worked out now rather than taken from the last
    // background refresh, which can be a refresh interval out of date. Then the
    // list is frozen for as long as the overlay is up.
    // Where you are standing, worked out before the marks are placed: on a Space of
    // its own it decides both of them.
    let screen = screenInFront
    let display = DisplayInfo.displayID(of: screen)
    let here = windowCoordinator.sections.first { $0.isCurrent && $0.id.displayID == display }
    let standing = here?.tiles.isEmpty == true ? here?.id : nil

    windowCoordinator.refreshActiveWindow(onADesktop: standing != nil)
    windowCoordinator.holdList()

    // The highlight is placed fresh every time: the window list has moved on since
    // the overlay was last open, and a stale index would point at another window.
    selection.index = OverlayGrid.initialIndex(
      for: windowCoordinator.targets, standingOn: standing)

    // The screen is chosen here rather than left to `center()`, which would use
    // whichever screen the window was last on. Measuring against one screen and
    // opening on another is how the fitting appeared to work only the second time.
    let fittingSize = place(window, on: screen)
    window.makeKeyAndOrderFront(nil)
    stepHotkeys?.start()
    NSApp.activate(ignoringOtherApps: true)
    logger.debug(
      "Overlay ordered front tiles=\(windowCoordinator.tiles.count) "
        + "fitting=\(Int(fittingSize.width))x\(Int(fittingSize.height)) "
        + "frame=\(Int(window.frame.width))x\(Int(window.frame.height)) "
        + "columns=\(fittedColumns) visible=\(window.isVisible) "
        + "key=\(window.isKeyWindow) appActive=\(NSApp.isActive) "
        + "frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") "
        + "selection=\(selection.index) (\(selectedApplicationName))"
    )
  }

  /// Centres the panel on a screen, at the size that screen's room allows.
  ///
  /// Size and position are committed as one frame, and drawn before the window is
  /// shown or moved. Set separately and left to be displayed whenever, they reached
  /// the window server after the order-front did: the panel appeared at the size
  /// and place it had last time — on the other screen, if that is where it was —
  /// and jumped to the new one 27ms later, which is what the flicker was.
  @discardableResult
  private func place(_ window: NSWindow, on screen: NSScreen?, animated: Bool = false) -> CGSize {
    let usable = screen?.visibleFrame ?? .zero
    let measuringStartedAt = Date()
    OverlayFittingCounters.measurements = 0
    let fittingSize = fitToScreen(within: usable.size)

    logger.debug(
      "Fitted the map in \(Int(Date().timeIntervalSince(measuringStartedAt) * 1000))ms "
        + "over \(OverlayFittingCounters.measurements) measurements")

    guard let placed = OverlayGrid.placement(for: fittingSize, in: usable) else {
      window.center()
      return fittingSize
    }

    let frame = window.frameRect(forContentRect: placed)
    guard animated else {
      window.setFrame(frame, display: true)
      return fittingSize
    }

    // Travelling rather than teleporting, so that the eye is led to the display the
    // window is on instead of having to find the panel again. Short enough that a
    // held-down arrow does not leave the panel trailing several steps behind.
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.followDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(frame, display: true)
    }

    return fittingSize
  }

  /// Names the tile the highlight starts on, so a log line can be checked against
  /// what the user was actually looking at.
  private var selectedApplicationName: String {
    let targets = windowCoordinator.targets
    guard targets.indices.contains(selection.index) else {
      return "none"
    }

    guard let tile = targets[selection.index].window else {
      return "an empty Space"
    }

    return "\(tile.displayAppName): \(tile.displayTitle)"
  }

  func hideOverlay() {
    stepHotkeys?.stop()

    steppingActivation = nil
    window?.orderOut(nil)
    windowCoordinator.releaseList()
    logger.debug("Overlay window ordered out")
  }

  /// Whether the overlay is actually in front of the user.
  ///
  /// A panel hides itself when its application is deactivated, and `isVisible`
  /// keeps saying `true` through that. Believing it made the hotkey close an
  /// overlay that was already gone, so the next press had to open it again — the
  /// overlay appeared to open only every second time.
  var isOverlayVisible: Bool {
    isPanelOnScreen
  }

  /// Whether the window server is actually showing the panel.
  ///
  /// `NSWindow.isVisible` cannot answer that on its own. It stays `true` for a
  /// panel that hid itself because the application was deactivated, and it is also
  /// `true` for one that is on screen while the application was refused activation
  /// — which is what happens over a fullscreen application. `NSApp.isActive` does
  /// not separate the two either: it is `false` in both.
  ///
  /// Getting it wrong is visible twice over. The hotkey re-presented a panel that
  /// was already up instead of closing it, and re-presenting places it on the
  /// screen the frontmost window is on, so the panel slid from one display to the
  /// other in front of the person pressing the key.
  ///
  /// The window server itself has no such doubt, and answering from it costs one
  /// lookup by window number.
  private var isPanelOnScreen: Bool {
    guard let window, window.isVisible else {
      return false
    }

    // Asked by listing what is on screen rather than by describing this one window:
    // `CGWindowListCreateDescriptionFromArray` answers with nothing at all for the
    // asking application's own window, measured on macOS 26.
    let onScreen =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

    return onScreen.contains { entry in
      (entry[kCGWindowNumber as String] as? Int) == window.windowNumber
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideOverlay()
    return false
  }

  /// Choosing a Space rather than a window: the overlay goes away and that Space
  /// comes up, which is the only way onto an empty desktop.
  func focusSpace(_ section: WindowSectionID) {
    guard let index = section.spaceIndex else {
      return
    }

    hideOverlay()

    // The overlay goes first and the Space changes last. With this application in
    // front, macOS answers a switch to an empty desktop by picking a front
    // application of its own — the one from the Space being left — and that
    // application brings its Space back with it.
    Task { @MainActor [weak self] in
      await self?.windowCoordinator.showSpace(
        at: index, on: section.displayID, handingBack: true)
    }
  }

  func selectWindow(id windowID: CGWindowID) {
    logger.info("Window selected from overlay")

    if config.closeAfterActivation {
      hideOverlay()
    }

    windowCoordinator.activateWindow(id: windowID)
  }

  private func closeSelectedWindow() {
    guard let tile = windowCoordinator.targets[safe: selection.index]?.window else {
      return
    }

    windowCoordinator.closeWindow(id: tile.id)
  }

  /// Finds the window a letter names, trying every reading of the key press.
  ///
  /// A key on a Cyrillic layout carries two letters: the one it prints and the
  /// Latin one in that position. Trying the printed one first for everything meant
  /// that pressing the key marked C on a Russian layout searched window titles for
  /// "с" before it ever considered Code — and with Russian titles on screen it
  /// often found one, which is what made the letters look like they were being
  /// confused.
  ///
  /// So the field decides before the reading does: an application name matched by
  /// either letter beats a window title matched by either.
  /// Moves the selection to the next window whose name starts with the key that
  /// was pressed — under any of the readings that key has.

  /// Return or Space: the window has been chosen, so this finishes — it comes
  /// forward and the overlay goes away, whatever `close_after_activation` says
  /// about picking a tile with the mouse or a number. Pressing the confirm key is
  /// the moment someone says they are done looking.
  func activateSelection() {
    selectWindow(at: selection.index)
    hideOverlay()
  }

  func selectWindow(at index: Int) {
    logger.info("Chosen at index \(index) of \(windowCoordinator.targets.count) targets")

    switch windowCoordinator.targets[safe: index] {
    case .window(let tile):
      selectWindow(id: tile.id)
    case .space(let section):
      focusSpace(section)
    case nil:
      return
    }
  }
}

extension OverlayWindowController {
  /// The panel's own look: transparent, shadowed, floating above ordinary windows
  /// and present on every Space, because the overlay is drawn over whatever is
  /// there rather than being a window among them.
  fileprivate static func dress(_ panel: OverlayPanel) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
  }
}

// MARK: - Choosing

/// Where the highlight goes and what it lands on.
extension OverlayWindowController {

  /// One window on inside the Space the highlight is in, and no further: this is
  /// the key that reaches the windows behind the front card when the arrows count
  /// in Spaces.
  func cycleWindow(forward: Bool) {
    defer { logger.info("Overlay cycled to index \(selection.index)") }

    selection.index = OverlayGrid.window(
      from: selection.index,
      forward: forward,
      sizes: windowCoordinator.sections.map(\.targets.count)
    )
  }

  func moveSelection(_ direction: OverlayGrid.Direction) {
    // At info level rather than debug: this is the line that says where the
    // highlight actually went, and a report of "it did nothing" is answered by
    // reading it back afterwards, which only works for what the system keeps.
    defer { logger.info("Overlay selection moved \(direction) to index \(selection.index)") }

    let sizes = windowCoordinator.sections.map(\.targets.count)
    let rows = OverlayGrid.spaceRows(
      ofDisplays: windowCoordinator.sections.map(\.id.displayID),
      perRow: fittedColumns,
      banded: config.overlayLayout.isBanded
    )

    selection.index =
      config.overlayArrows == .spaces
      ? OverlayGrid.space(from: selection.index, moving: direction, sizes: sizes, rows: rows)
      : OverlayGrid.index(from: selection.index, moving: direction, sizes: sizes, rows: rows)
  }

  /// Sends the chosen window to the display the arrow points at.
  ///
  /// The arrow means on the map what it means everywhere else on it: the group in
  /// that direction. When that group belongs to another display the window is sent
  /// there; when it is another Space of the same display there is nothing to do,
  /// because no public interface — and, on this system, no private one either —
  /// will move a window between Spaces.
  private func sendWindow(_ direction: OverlayGrid.Direction) {
    let sizes = windowCoordinator.sections.map(\.targets.count)
    let target = OverlayGrid.space(
      from: selection.index,
      moving: direction,
      sizes: sizes,
      rows: OverlayGrid.spaceRows(
        ofDisplays: windowCoordinator.sections.map(\.id.displayID), perRow: fittedColumns)
    )

    guard let tile = windowCoordinator.targets[safe: selection.index]?.window,
      let group = OverlayGrid.starts(of: sizes).lastIndex(where: { $0 <= target }),
      let landing = windowCoordinator.sections[safe: group]
    else {
      return
    }

    send(tile, to: landing.id.displayID)
  }

  /// A tile dropped on another: a rearrangement when they share a display, and a
  /// move to the other screen when they do not.
  func moveOrSend(_ windowID: CGWindowID, onto targetID: CGWindowID) {
    let tiles = windowCoordinator.sections.flatMap(\.tiles)

    guard let moving = tiles.first(where: { $0.id == windowID }),
      let target = tiles.first(where: { $0.id == targetID })
    else {
      return
    }

    guard moving.displayID != target.displayID else {
      windowCoordinator.moveTile(windowID, before: targetID)
      return
    }

    send(moving, to: target.displayID)
  }

  private func send(_ tile: WindowTileModel, to displayID: CGDirectDisplayID) {
    guard tile.displayID != displayID else {
      // The arrow pointed at another Space of the same display, and moving a window
      // between Spaces is the one thing macOS keeps to itself.
      logger.info("Nothing to send: the window is already on display \(displayID)")
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      guard await onWindow(tile, { windowCoordinator.sendWindow($0, toDisplay: displayID) })
      else {
        logger.info("Could not send \(tile.displayAppName) to display \(displayID)")
        return
      }

      // The map is the list of where things are, so it has to be asked again before
      // it can say the window is somewhere else.
      await windowCoordinator.refreshNow(force: true)
      followTheStep(toDisplay: displayID)
    }
  }

  /// Does something to a window, showing its Space first if that is what it takes.
  ///
  /// Accessibility does not list a window whose Space is not showing, and a window
  /// it will not list cannot be touched at all — so the Space is shown and the
  /// action tried again, which is the same thing a person would have to do before
  /// reaching for the window themselves.
  private func onWindow(
    _ tile: WindowTileModel,
    _ action: @MainActor (WindowTileModel) -> Bool
  ) async -> Bool {
    if action(tile) {
      return true
    }

    guard let space = tile.spaceIndex else {
      return false
    }

    await windowCoordinator.showSpace(at: space, on: tile.displayID, handingBack: false)

    return action(tile)
  }

  /// Puts the chosen window in a part of the screen it is on.
  private func place(_ placement: WindowPlacement) {
    guard let tile = windowCoordinator.targets[safe: selection.index]?.window else {
      logger.info("Nothing to place: the highlight is on a Space, not a window")
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      guard await onWindow(tile, { windowCoordinator.placeWindow($0, placement) }) else {
        logger.info("Could not place \(tile.displayAppName)")
        return
      }

      await windowCoordinator.refreshNow(force: true)
    }
  }

  /// Hands the chosen window to its application's own fullscreen mode.
  private func putFullscreen() {
    guard let tile = windowCoordinator.targets[safe: selection.index]?.window else {
      logger.info("Nothing to put fullscreen: the highlight is on a Space, not a window")
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      guard await onWindow(tile, { windowCoordinator.toggleFullscreen($0) }) else {
        logger.info("Could not put \(tile.displayAppName) fullscreen")
        return
      }

      // A window going fullscreen takes a Space of its own, so the map it was drawn
      // on is out of date the moment it happens.
      await windowCoordinator.refreshNow(force: true)
    }
  }

  private func moveTile(_ direction: OverlayGrid.Direction) {
    let target = OverlayGrid.index(
      from: selection.index,
      moving: direction,
      sizes: windowCoordinator.sections.map(\.targets.count),
      rows: OverlayGrid.spaceRows(
        ofDisplays: windowCoordinator.sections.map(\.id.displayID), perRow: fittedColumns)
    )

    guard windowCoordinator.swapTiles(at: selection.index, with: target) else {
      return
    }

    selection.index = target
  }
}

// MARK: - Focus

/// Who has the keyboard while the overlay is up, and what the overlay does about
/// another application taking it.
extension OverlayWindowController {

  /// Puts the overlay away when something else comes forward.
  ///
  /// This is what `hidesOnDeactivate` used to do, and it does it in the case that
  /// one missed: the application is refused activation over a fullscreen window,
  /// never becomes active, and so is never deactivated either — leaving the panel
  /// on screen with nothing to take it down.
  ///
  /// Including one the overlay itself asked for. Letting that one through sounded
  /// right — `config.closeAfterActivation` off means the overlay stays up while windows
  /// are picked from it — but it is not what the panel used to do: AppKit hid it
  /// whenever this application was deactivated, whoever had taken over. Picking a
  /// window left the overlay on screen, which reads as an overlay that will not go
  /// away. Stepping through windows still keeps it, because a step raises a window
  /// without activating its application, and nothing comes forward.
  private func observeOtherApplications() {
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      // Which application arrived is read from the notification rather than asked
      // of the workspace afterwards: asked afterwards, the answer was sometimes
      // still the application that had just left, and the overlay hid itself the
      // instant it was shown.
      let activated =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let arrived = activated?.processIdentifier

      // Registered against the main queue, so the hop is a formality rather than a
      // thread change.
      MainActor.assumeIsolated {
        guard let self, let arrived,
          arrived != ProcessInfo.processInfo.processIdentifier
        else {
          return
        }

        guard arrived != self.steppingActivation else {
          self.steppingActivation = nil
          self.reclaimTheKeyboard()
          return
        }

        // A step changes the Space, and macOS answers that by bringing forward
        // whichever application owns the Space arrived at — measured, a step put
        // Code in front and the overlay took that for the user walking away and
        // ordered itself out mid-ride. Only the application this asked for can be
        // named in advance; the system's own choice cannot, so a step is instead
        // given a moment in which any arrival belongs to it.
        if let until = self.steppingUntil, ContinuousClock.now < until {
          self.logger.debug(
            "Keeping the overlay: \(activated?.localizedName ?? "?") came forward mid-step")
          self.reclaimTheKeyboard()
          return
        }

        self.logger.debug(
          "Hiding: \(activated?.localizedName ?? "?") came forward (pid \(arrived))")
        self.hideOverlay()
      }
    }
  }

  /// Takes the keyboard back after a step brought another application forward.
  ///
  /// A non-activating panel can be made key without its application becoming
  /// active, which is the only way this could work: the overlay is meant to be
  /// what you are typing at, and the application it just raised a window in is
  /// meant to be what you are looking at.
  private func reclaimTheKeyboard() {
    guard let window, window.isVisible else {
      return
    }

    // The application has to come back with it. A panel of an inactive application
    // cannot be made key, so ordering it front alone left the keys going to whoever
    // was in front — and an arrow nobody handles is what macOS answers with a beep,
    // over and over while the key is held. That was the sound.
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    logger.debug("Took the keyboard back after a step; key=\(window.isKeyWindow)")
  }

  /// Called when the application stops, because the observer outlives the window.
  func stopObserving() {
    guard let activationObserver else {
      return
    }

    NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
    self.activationObserver = nil
  }
}

// MARK: - Stepping

/// Moving across the overlay as if it were a map: the highlight moves, the window
/// under it comes forward, and the panel follows to the display that window is on.
extension OverlayWindowController {

  /// The typed character first, then the Latin letter the same physical key
  /// carries. On a Cyrillic layout those differ, and an application named in Latin
  /// would otherwise be unreachable by its own initial.
  /// Moves the highlighted tile itself, and takes the highlight with it.
  /// Moves the highlight and brings that window forward, leaving the overlay up.
  ///
  /// The window is raised without its application being activated. Activating
  /// takes the key window away, and taking it back afterwards proved unreliable:
  /// after one step the overlay stopped receiving keys, which looked like it had
  /// hung. Worse, when Accessibility cannot aim at the window, activating raises
  /// whatever it can instead — stepping onto a Finder window landed on the desktop.
  ///
  /// Raising alone keeps the keyboard here and does nothing at all when it cannot
  /// aim. It also does not cross Spaces: a window on another Space comes forward
  /// within its own, which is as far as this can go without a switch that would
  /// take the screen away from the overlay.
  func stepAndActivate(_ direction: OverlayGrid.Direction) {
    let startedAt = Date()
    steppingUntil = ContinuousClock.now + .seconds(config.activationSettleSeconds)
    // Switching to a window on another Space runs a system animation of about half
    // a second, and presses arriving faster than that queue up behind each other —
    // which is what makes a held-down arrow look like the overlay has hung. A step
    // that arrives too soon moves the highlight and lets the switch wait for the
    // next one.
    moveSelection(direction)

    guard let target = windowCoordinator.targets[safe: selection.index] else {
      return
    }

    guard let stepped = target.window else {
      // Stepping onto an empty Space shows it: there is no window there to raise.
      if case .space(let section) = target, let index = section.spaceIndex {
        // Showing a Space hands the keyboard to Finder, and that arrival would
        // otherwise put the overlay away. It is marked as one to survive, exactly
        // as an activation caused by stepping onto a window is — without the
        // handover the switch does not hold: this application stays in front of a
        // desktop it owns no window on, and macOS takes the Space back.
        steppingActivation = DesktopSwitcher.desktopOwner?.processIdentifier

        Task { @MainActor [weak self] in
          await self?.windowCoordinator.showSpace(
            at: index, on: section.displayID, handingBack: true)
          self?.followTheStep(toDisplay: section.displayID)
        }
      }

      return
    }

    let tile = stepped

    // Accessibility first, because raising without activating brings nothing
    // forward and so disturbs nothing. It only reaches the Space showing now,
    // though, and a step onto any other one used to do nothing at all — the
    // highlight moved and the window stayed where it was. So the full path is
    // asked next, and the activation it causes is marked as one to survive.
    var raised = windowCoordinator.raiseWindow(id: tile.id)
    if !raised {
      steppingActivation = tile.processID

      Task { @MainActor [weak self] in
        guard let self else {
          return
        }

        // A desktop is shown by its own shortcut and the window raised once it is
        // there; a fullscreen Space has no shortcut, and its one window is reached
        // the only way left, by activating the application that fills it.
        //
        // Activation cannot do the first case: macOS refuses to bring an
        // application forward over a fullscreen Space, so stepping left off
        // Spotify's Space stayed on Spotify however often it was pressed, while
        // stepping the other way worked.
        if let space = tile.spaceIndex, !self.showsTheSpace(of: tile) {
          await self.windowCoordinator.showSpace(
            at: space, on: tile.displayID, handingBack: true)
          _ = self.windowCoordinator.raiseWindow(id: tile.id)
        } else {
          self.windowCoordinator.activateWindow(id: tile.id)
        }
      }

      raised = true
    }
    followTheStep(to: tile)
    logger.debug(
      "Stepped to index \(selection.index) in \(Int(Date().timeIntervalSince(startedAt) * 1000))ms; "
        + "raised=\(raised) "
        + "key=\(window?.isKeyWindow == true) appActive=\(NSApp.isActive) "
        + "frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
  }

  /// Whether the display is already showing the Space this window is on.
  private func showsTheSpace(of tile: WindowTileModel) -> Bool {
    windowCoordinator.sections.contains {
      $0.isCurrent && $0.id.displayID == tile.displayID && $0.id.spaceIndex == tile.spaceIndex
    }
  }

  /// Moves the overlay to the display the window just stepped onto lives on.
  ///
  /// Stepping is for finding a window by looking at it, and looking at a window on
  /// the other display while the list of them stays on this one means looking in
  /// two places at once. The panel only moves when the display actually changes:
  /// re-placing it on every step would shift it by whatever the new screen's room
  /// allows, for no reason.
  private func followTheStep(to tile: WindowTileModel) {
    followTheStep(toDisplay: tile.displayID)
  }

  private func followTheStep(toDisplay displayID: CGDirectDisplayID) {
    guard let window,
      let screen = DisplayInfo.screen(for: displayID),
      screen !== window.screen
    else {
      return
    }

    place(window, on: screen, animated: true)
    logger.debug("Overlay followed the step to \(screen.localizedName)")
  }
}
