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
  private let logger: AppLogger
  private let hostingView: NSHostingView<OverlayView>
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
    self.logger = AppLogger(debugMode: debugMode, category: .overlay)
    self.hostingView = NSHostingView(
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
    panel.contentView = hostingView

    panel.onSelectIndex = { [weak self] index in
      self?.selectWindow(at: index)
    }
    panel.onMoveSelection = { [weak self] direction in
      self?.moveSelection(direction)
    }
    panel.onMoveTile = { [weak self] direction in
      self?.moveTile(direction)
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

    // The grid wraps to a second row once there are more than six windows, so the
    // panel is sized to its content at show time rather than pinned to a constant.
    let fittingSize = hostingView.fittingSize
    if fittingSize.width > 0, fittingSize.height > 0 {
      window.setContentSize(fittingSize)
    }

    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    logger.debug(
      "Overlay ordered front tiles=\(windowCoordinator.tiles.count) "
        + "fitting=\(Int(fittingSize.width))x\(Int(fittingSize.height)) "
        + "frame=\(Int(window.frame.width))x\(Int(window.frame.height)) "
        + "visible=\(window.isVisible) "
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

    return tiles[selection.index].displayAppName
  }

  func hideOverlay() {
    window?.orderOut(nil)
    windowCoordinator.releaseList()
    logger.debug("Overlay window ordered out")
  }

  var isOverlayVisible: Bool {
    window?.isVisible == true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideOverlay()
    return false
  }

  private func makeOverlayView() -> OverlayView {
    OverlayView(
      windowCoordinator: windowCoordinator,
      selection: selection,
      background: background,
      columns: columns,
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
        maximum: columns
      )
    )
  }

  /// The typed character first, then the Latin letter the same physical key
  /// carries. On a Cyrillic layout those differ, and an application named in Latin
  /// would otherwise be unreachable by its own initial.
  /// Moves the highlighted tile itself, and takes the highlight with it.
  private func moveTile(_ direction: OverlayGrid.Direction) {
    let target = OverlayGrid.index(
      from: selection.index,
      moving: direction,
      rows: OverlayGrid.rows(
        forSectionSizes: windowCoordinator.sections.map(\.tiles.count),
        maximum: columns
      )
    )

    guard windowCoordinator.swapTiles(at: selection.index, with: target) else {
      return
    }

    selection.index = target
  }

  private func jumpToName(typed: Character, orLatin latin: Character?) {
    let tiles = windowCoordinator.tiles
    let match =
      OverlayGrid.index(from: selection.index, matching: typed, in: tiles)
      ?? latin.flatMap { OverlayGrid.index(from: selection.index, matching: $0, in: tiles) }

    guard let match else {
      return
    }

    selection.index = match
    logger.debug("Overlay selection jumped to index \(match) on \(typed)")
  }

  private func closeSelectedWindow() {
    guard windowCoordinator.tiles.indices.contains(selection.index) else {
      return
    }

    windowCoordinator.closeWindow(id: windowCoordinator.tiles[selection.index].id)
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

final class OverlayPanel: NSPanel {
  var onSelectIndex: ((Int) -> Void)?
  var onMoveSelection: ((OverlayGrid.Direction) -> Void)?
  var onMoveTile: ((OverlayGrid.Direction) -> Void)?
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

      if modifiers == [.shift] {
        onMoveTile?(direction)
      } else {
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
