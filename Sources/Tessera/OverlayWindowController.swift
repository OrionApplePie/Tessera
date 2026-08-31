import AppKit
import Carbon.HIToolbox
import SwiftUI

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
  private let windowCoordinator: WindowCoordinator
  private let closeAfterActivation: Bool
  private let background: OverlayColor
  private let columns: Int
  private let dimsStaleThumbnails: Bool
  private let closeHotkey: HotkeyBinding?
  private var isPresenting = false
  /// The configured column count, widened when the overlay would otherwise be
  /// taller than the screen it opens on.
  private var fittedColumns: Int
  private let logger: AppLogger
  private let hostingView: TransparentHostingView<OverlayView>
  private let selection = OverlaySelection()

  init(
    windowCoordinator: WindowCoordinator,
    closeAfterActivation: Bool = true,
    background: OverlayColor = AppConfig.default.overlayBackground,
    columns: Int = AppConfig.default.overlayColumns,
    dimsStaleThumbnails: Bool = AppConfig.default.dimsStaleThumbnails,
    closeHotkey: HotkeyBinding? = AppConfig.default.closeHotkey,
    debugMode: Bool = false
  ) {
    self.windowCoordinator = windowCoordinator
    self.closeAfterActivation = closeAfterActivation
    self.background = background
    self.columns = columns
    self.dimsStaleThumbnails = dimsStaleThumbnails
    self.closeHotkey = closeHotkey
    self.fittedColumns = columns
    self.logger = AppLogger(debugMode: debugMode, category: .overlay)
    self.hostingView = TransparentHostingView(
      rootView: OverlayView(
        windowCoordinator: windowCoordinator,
        selection: OverlaySelection(),
        background: background,
        columns: columns,
        dimsStaleThumbnails: dimsStaleThumbnails,
        onSelect: { _ in },
        onMove: { _, _ in },
        onClose: {}
      ))

    let panel = OverlayPanel(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 260),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    super.init(window: panel)

    panel.delegate = self
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

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
    hostingView.layer?.cornerRadius = TileMetrics.surfaceCornerRadius
    hostingView.layer?.cornerCurve = .continuous
    hostingView.layer?.masksToBounds = true

    // The panel is painted at the layer as well as by the view inside it. The
    // fitting pass measures a view that is not in a window and lands a little over
    // what the same view settles at once it is, and with the window no longer
    // resizing itself to the view that difference would show as a transparent band
    // along the edge. Same colour, so where the two meet is not visible.
    hostingView.layer?.backgroundColor = CGColor(
      srgbRed: background.red,
      green: background.green,
      blue: background.blue,
      alpha: background.alpha
    )

    panel.contentView = hostingView

    connect(panel)
  }

  /// The panel reports what was pressed; this is where each of those becomes an
  /// action on the list.
  private func connect(_ panel: OverlayPanel) {
    panel.onSelectIndex = { [weak self] index in
      self?.selectWindow(at: index)
    }
    panel.onMoveSelection = { [weak self] direction in
      self?.moveSelection(direction)
    }
    panel.onMoveTile = { [weak self] direction in
      self?.moveTile(direction)
    }
    panel.onStepAndActivate = { [weak self] direction in
      self?.stepAndActivate(direction)
    }
    panel.closeHotkey = closeHotkey
    panel.onCloseWindow = { [weak self] in
      self?.closeSelectedWindow()
    }
    panel.onJumpToName = { [weak self] typed, latin in
      self?.jumpToName(typed: typed, orLatin: latin)
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

    // Which window you came from is worked out now rather than taken from the last
    // background refresh, which can be a refresh interval out of date. Then the
    // list is frozen for as long as the overlay is up.
    windowCoordinator.refreshActiveWindow()
    windowCoordinator.holdList()

    // The highlight is placed fresh every time: the window list has moved on since
    // the overlay was last open, and a stale index would point at another window.
    selection.index = OverlayGrid.initialIndex(for: windowCoordinator.tiles)

    // The screen is chosen here rather than left to `center()`, which would use
    // whichever screen the window was last on. Measuring against one screen and
    // opening on another is how the fitting appeared to work only the second time.
    let screen = NSScreen.main
    let usable = screen?.visibleFrame ?? .zero

    // The panel is sized to its content at show time rather than pinned to a
    // constant, and the content is laid out to fit the screen it opens on.
    let fittingSize = fitToScreen(within: usable.size)

    // Size and position are committed as one frame, and drawn before the panel is
    // ordered front. Set separately and left to be displayed whenever, they reached
    // the window server after the order-front did: the panel appeared at the size
    // and place it had last time — on the other screen, if that is where it was —
    // and jumped to the new one 27ms later, which is what the flicker was.
    if let placed = OverlayGrid.placement(for: fittingSize, in: usable) {
      window.setFrame(window.frameRect(forContentRect: placed), display: true)
    } else {
      window.center()
    }

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    logger.debug(
      "Overlay ordered front tiles=\(windowCoordinator.tiles.count) "
        + "fitting=\(Int(fittingSize.width))x\(Int(fittingSize.height)) "
        + "frame=\(Int(window.frame.width))x\(Int(window.frame.height)) "
        + "columns=\(fittedColumns) visible=\(window.isVisible) "
        + "selection=\(selection.index) (\(selectedApplicationName))"
    )
  }

  /// Names the tile the highlight starts on, so a log line can be checked against
  /// what the user was actually looking at.
  private var selectedApplicationName: String {
    let tiles = windowCoordinator.tiles
    guard tiles.indices.contains(selection.index) else {
      return "none"
    }

    return "\(tiles[selection.index].displayAppName): \(tiles[selection.index].displayTitle)"
  }

  func hideOverlay() {
    // Restored so that the overlay is transient again once this round of stepping
    // through windows is over.
    (window as? NSPanel)?.hidesOnDeactivate = true
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
    window?.isVisible == true && NSApp.isActive
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideOverlay()
    return false
  }

  /// Widens the grid until it is no taller than the screen, or until no more tiles
  /// fit across it.
  ///
  /// The configured column count is where this starts, not what it insists on: a
  /// column count that reads well with six windows leaves sixteen taller than a
  /// laptop screen, and a switcher nobody can see all of is not doing its job.
  /// Measured rather than calculated — SwiftUI's own fitting size is the only
  /// answer that accounts for the headings.
  private func fitToScreen(within usable: CGSize) -> CGSize {
    let widest = TileMetrics.columnsFitting(availableWidth: usable.width)

    var chosen = columns
    var size = measure(columns: chosen)

    while size.height > usable.height, chosen < widest {
      chosen += 1
      size = measure(columns: chosen)
    }

    fittedColumns = chosen
    hostingView.rootView = makeOverlayView()
    return size
  }

  /// Measured on a throwaway view rather than on the one on screen: an
  /// `NSHostingView` does not re-report its fitting size synchronously when its
  /// root view is replaced, so asking the live view in a loop returns the first
  /// answer every time — which is how the first version of this widened the grid
  /// to the edge of the screen and then sized the window for the layout it had
  /// rejected.
  private func measure(columns count: Int) -> CGSize {
    TransparentHostingView(rootView: makeOverlayView(columns: count)).fittingSize
  }

  private func makeOverlayView(columns count: Int? = nil) -> OverlayView {
    OverlayView(
      windowCoordinator: windowCoordinator,
      selection: selection,
      background: background,
      columns: count ?? fittedColumns,
      dimsStaleThumbnails: dimsStaleThumbnails,
      onSelect: { [weak self] windowID in
        self?.selectWindow(id: windowID)
      },
      onMove: { [weak self] windowID, targetID in
        self?.windowCoordinator.moveTile(windowID, before: targetID)
      },
      onClose: { [weak self] in
        self?.hideOverlay()
      }
    )
  }

  private func selectWindow(id windowID: CGWindowID) {
    logger.info("Window selected from overlay")

    if closeAfterActivation {
      hideOverlay()
    }

    windowCoordinator.activateWindow(id: windowID)
  }

  private func moveSelection(_ direction: OverlayGrid.Direction) {
    defer { logger.debug("Overlay selection moved \(direction) to index \(selection.index)") }

    selection.index = OverlayGrid.index(
      from: selection.index,
      moving: direction,
      rows: OverlayGrid.rows(
        forSectionSizes: windowCoordinator.sections.map(\.tiles.count),
        maximum: fittedColumns
      )
    )
  }

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
  private func stepAndActivate(_ direction: OverlayGrid.Direction) {
    // Switching to a window on another Space runs a system animation of about half
    // a second, and presses arriving faster than that queue up behind each other —
    // which is what makes a held-down arrow look like the overlay has hung. A step
    // that arrives too soon moves the highlight and lets the switch wait for the
    // next one.
    moveSelection(direction)

    guard windowCoordinator.tiles.indices.contains(selection.index) else {
      return
    }

    let raised = windowCoordinator.raiseWindow(id: windowCoordinator.tiles[selection.index].id)
    logger.debug("Stepped to index \(selection.index); raised=\(raised)")
  }

  private func moveTile(_ direction: OverlayGrid.Direction) {
    let target = OverlayGrid.index(
      from: selection.index,
      moving: direction,
      rows: OverlayGrid.rows(
        forSectionSizes: windowCoordinator.sections.map(\.tiles.count),
        maximum: fittedColumns
      )
    )

    guard windowCoordinator.swapTiles(at: selection.index, with: target) else {
      return
    }

    selection.index = target
  }

  private func closeSelectedWindow() {
    guard windowCoordinator.tiles.indices.contains(selection.index) else {
      return
    }

    windowCoordinator.closeWindow(id: windowCoordinator.tiles[selection.index].id)
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
  private func jumpToName(typed: Character, orLatin latin: Character?) {
    let tiles = windowCoordinator.tiles
    let readings = [typed, latin].compactMap { $0 }
    let fields: [OverlayGrid.MatchField] = [.applicationName, .windowTitle]

    for field in fields {
      for character in readings {
        guard
          let match = OverlayGrid.index(
            from: selection.index, matching: character, in: tiles, field: field)
        else {
          continue
        }

        selection.index = match
        logger.debug(
          "Overlay selection jumped to index \(match) (\(selectedApplicationName)) "
            + "on \(character) in \(field)")
        return
      }
    }
  }

  private func activateSelection() {
    selectWindow(at: selection.index)
  }

  private func selectWindow(at index: Int) {
    guard windowCoordinator.tiles.indices.contains(index) else {
      return
    }

    selectWindow(id: windowCoordinator.tiles[index].id)
  }
}

/// A hosting view that does not paint over the shape its content draws.
///
/// `NSHostingView` fills its own bounds with an opaque background, which squares
/// off the rounded corners the overlay draws for itself — measured as a single
/// anti-aliased pixel at the corner of an otherwise solid rectangle. No property
/// turns that off, so the view declares itself transparent instead.
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool {
    false
  }

  required init(rootView: Content) {
    super.init(rootView: rootView)

    wantsLayer = true
    layer?.backgroundColor = .clear
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

final class OverlayPanel: NSPanel {
  var onSelectIndex: ((Int) -> Void)?
  var onMoveSelection: ((OverlayGrid.Direction) -> Void)?
  var onMoveTile: ((OverlayGrid.Direction) -> Void)?
  var onStepAndActivate: ((OverlayGrid.Direction) -> Void)?
  var onJumpToName: ((Character, Character?) -> Void)?
  var onCloseWindow: (() -> Void)?
  var closeHotkey: HotkeyBinding?
  var onActivateSelection: (() -> Void)?
  var onDismiss: (() -> Void)?

  /// Space activates alongside Return: after ctrl+alt+space opened the overlay it
  /// is the key already under the thumb.
  private static let activationKeyCodes: Set<UInt16> = [
    UInt16(kVK_Return),
    UInt16(kVK_ANSI_KeypadEnter),
    UInt16(kVK_Space),
  ]

  private static let directionsByKeyCode: [UInt16: OverlayGrid.Direction] = [
    UInt16(kVK_LeftArrow): .left,
    UInt16(kVK_RightArrow): .right,
    UInt16(kVK_UpArrow): .up,
    UInt16(kVK_DownArrow): .down,
  ]

  override var canBecomeKey: Bool {
    true
  }

  /// A shortcut with a command or control key never reaches `keyDown`: AppKit
  /// offers it to the responder chain as a key equivalent first, and beeps if
  /// nobody claims it. Which is exactly what the first attempt at closing a window
  /// from here did.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard matchesCloseHotkey(event) else {
      return super.performKeyEquivalent(with: event)
    }

    onCloseWindow?()
    return true
  }

  private func matchesCloseHotkey(_ event: NSEvent) -> Bool {
    closeHotkey?.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) == true
  }

  /// A bare letter, if that is what this is.
  ///
  /// Shift and caps lock are ignored rather than excluded: they change the letter,
  /// not the intent. Any other modifier means the key belongs to somebody else.
  private static func jumpCharacter(for event: NSEvent) -> Character? {
    let modifiers = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.shift, .capsLock])

    guard modifiers.isEmpty,
      let character = event.charactersIgnoringModifiers?.first,
      character.isLetter
    else {
      return nil
    }

    return character
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) || event.charactersIgnoringModifiers == "\u{1b}" {
      onDismiss?()
      return
    }

    if let direction = Self.directionsByKeyCode[event.keyCode] {
      // Arrow keys always carry the function and numeric pad flags, so only shift
      // distinguishes moving a tile from moving the highlight.
      let modifiers = event.modifierFlags
        .intersection(.deviceIndependentFlagsMask)
        .subtracting([.capsLock, .function, .numericPad])

      switch modifiers {
      case [.shift]:
        onMoveTile?(direction)
      case [.control, .shift]:
        onStepAndActivate?(direction)
      default:
        onMoveSelection?(direction)
      }

      return
    }

    if Self.activationKeyCodes.contains(event.keyCode) {
      onActivateSelection?()
      return
    }

    let digit = event.charactersIgnoringModifiers.flatMap { Int($0) }
    if let digit, (1...9).contains(digit) {
      onSelectIndex?(digit - 1)
      return
    }

    // A binding without a command or control key arrives here rather than as a key
    // equivalent, so both doors are watched.
    if matchesCloseHotkey(event) {
      onCloseWindow?()
      return
    }

    if let character = Self.jumpCharacter(for: event) {
      onJumpToName?(character, HotkeyKey.latinLetter(forKeyCode: event.keyCode))
      return
    }

    super.keyDown(with: event)
  }
}
