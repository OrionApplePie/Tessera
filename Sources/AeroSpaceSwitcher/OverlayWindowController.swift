import AppKit
import SwiftUI

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    private let previewCoordinator: PreviewCoordinator
    private let closeAfterWorkspaceSwitch: Bool
    private let logger: AppLogger

    init(previewCoordinator: PreviewCoordinator, closeAfterWorkspaceSwitch: Bool = true, debugMode: Bool = false) {
        self.previewCoordinator = previewCoordinator
        self.closeAfterWorkspaceSwitch = closeAfterWorkspaceSwitch
        self.logger = AppLogger(debugMode: debugMode, category: .overlay)

        let window = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1_450, height: 290),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.contentView = NSHostingView(rootView: makeOverlayView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showOverlay() {
        guard let window else {
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logger.debug("Overlay window ordered front")
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
            previewCoordinator: previewCoordinator,
            onSelect: { [weak self] workspaceID in
                self?.selectWorkspace(workspaceID)
            },
            onClose: { [weak self] in
                self?.hideOverlay()
            }
        )
    }

    private func selectWorkspace(_ workspaceID: String) {
        logger.info("Workspace selected from overlay")
        previewCoordinator.switchWorkspace(workspaceID)
        if closeAfterWorkspaceSwitch {
            hideOverlay()
        }
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            orderOut(nil)
            return
        }

        super.keyDown(with: event)
    }
}
