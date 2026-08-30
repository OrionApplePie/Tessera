import AppKit
import Carbon.HIToolbox
import SwiftUI

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
  private let windowCoordinator: WindowCoordinator
  private let closeAfterActivation: Bool
  private let background: OverlayColor
  private let logger: AppLogger
  private let hostingView: NSHostingView<OverlayView>
  private let selection = OverlaySelection()

  init(
    windowCoordinator: WindowCoordinator,
    closeAfterActivation: Bool = true,
    background: OverlayColor = AppConfig.default.overlayBackground,
    debugMode: Bool = false
  ) {
    self.windowCoordinator = windowCoordinator
    self.closeAfterActivation = closeAfterActivation
    self.background = background
    self.logger = AppLogger(debugMode: debugMode, category: .overlay)
    self.hostingView = NSHostingView(
      rootView: OverlayView(
        windowCoordinator: windowCoordinator,
        selection: OverlaySelection(),
        background: background,
        onSelect: { _ in },
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
        + "visible=\(window.isVisible)"
    )
  }

  func hideOverlay() {
    window?.orderOut(nil)
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
      onSelect: { [weak self] windowID in
        self?.selectWindow(id: windowID)
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
        forSectionSizes: windowCoordinator.sections.map(\.tiles.count))
    )
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

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) || event.charactersIgnoringModifiers == "\u{1b}" {
      onDismiss?()
      return
    }

    if let direction = Self.directionsByKeyCode[event.keyCode] {
      onMoveSelection?(direction)
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

    super.keyDown(with: event)
  }
}
