import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

/// What one pass over ScreenCaptureKit found: every switchable window, neither
/// ordered nor capped, plus what is known about the displays.
///
/// Ordering is left to the caller because it needs what only the caller knows —
/// the background app has learned which Space a window is on, a one-shot CLI
/// command has not.
struct WindowSnapshot: Sendable {
  let windows: [WindowInfo]
  let displayNames: [CGDirectDisplayID: String]
  let displayOrder: [CGDirectDisplayID]
}

/// Enumerates the on-screen windows Tessera can switch between.
///
/// ScreenCaptureKit is the source of truth because it is also what captures the
/// thumbnails: enumerating and capturing through the same framework means a tile
/// and its preview always refer to the same `CGWindowID`, with no fuzzy matching.
@MainActor
struct WindowListService {
  private let config: AppConfig
  private let maxWindows: Int
  private let logger: AppLogger
  private let minimizedWindowService: MinimizedWindowService
  private let learnedWindows: LearnedWindowStore

  /// Windows smaller than this in either dimension are panels, popovers and
  /// status-bar scraps rather than things a user would switch to.
  private static let minimumWindowEdge: CGFloat = 40

  init(config: AppConfig = .default, learnedWindows: LearnedWindowStore? = nil) {
    self.config = config
    self.learnedWindows =
      learnedWindows ?? LearnedWindowStore(debugMode: config.debugMode)
    self.maxWindows = config.maxWindows
    self.logger = AppLogger(debugMode: config.debugMode, category: .capture)
    self.minimizedWindowService = MinimizedWindowService(config: config)
  }

  func snapshot() async throws -> WindowSnapshot {
    let content = try await SCShareableContent.current
    let ownProcessID = ProcessInfo.processInfo.processIdentifier
    let names = DisplayInfo.localizedNames()

    let displays = content.displays.map { display in
      DisplayInfo(
        id: display.displayID,
        name: names[display.displayID] ?? "Display \(display.displayID)",
        frame: display.frame
      )
    }

    // Windows are switchable whatever the display list says, so there is always a
    // display id to file them under, even if that list came back empty.
    let mainDisplayID = CGMainDisplayID()
    let fallbackDisplayID =
      displays.first { $0.id == mainDisplayID }?.id ?? displays.first?.id ?? mainDisplayID
    let displayOrder = DisplayInfo.order(of: displays)

    let candidates =
      content.windows
      .filter { window in
        guard let owner = window.owningApplication else {
          return false
        }

        // Untitled layer-0 windows are the shadow and overlay helpers apps keep
        // around; they are not places a user can switch to.
        //
        // `isOnScreen` is deliberately not required: a window on another Space or
        // a minimized one is exactly what a switcher is for.
        return window.windowLayer == 0
          && !(window.title ?? "").isEmpty
          && !config.ignores(applicationNamed: owner.applicationName)
          && !isLearnedAbsent(window, applicationName: owner.applicationName)
          && window.frame.width >= Self.minimumWindowEdge
          && window.frame.height >= Self.minimumWindowEdge
          && owner.processID != ownProcessID
      }
      .map { window in
        (window, window.owningApplication?.processID ?? 0)
      }

    let minimized = minimizedWindowService.minimizedWindows(
      forProcessIDs: Set(candidates.filter { !$0.0.isOnScreen }.map(\.1)))

    let windows =
      candidates
      .map { window, processID in
        WindowInfo(
          id: window.windowID,
          appName: window.owningApplication?.applicationName ?? "",
          title: window.title ?? "",
          processID: processID,
          frame: window.frame,
          isOnScreen: window.isOnScreen,
          isMinimized: minimized.contains(processID: processID, title: window.title ?? ""),
          displayID: DisplayInfo.display(for: window.frame, among: displays)?.id
            ?? fallbackDisplayID
        )
      }

    logger.debug(
      "Discovered \(windows.count) switchable windows across \(displays.count) display(s), "
        + "\(windows.count { !$0.isOnScreen }) of them off the current Space, "
        + "\(windows.count(where: \.isMinimized)) minimized"
    )

    return WindowSnapshot(
      windows: windows,
      displayNames: Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.name) }),
      displayOrder: displayOrder
    )
  }

  /// Whether a window was learned not to come forward when activated.
  ///
  /// A learned window that turns up on screen has plainly come back to life —
  /// someone opened it from the tray — so the lesson is dropped rather than kept
  /// hiding a window the user can see.
  private func isLearnedAbsent(_ window: SCWindow, applicationName: String) -> Bool {
    let signature = WindowSignature(
      applicationName: applicationName,
      title: window.title ?? ""
    )

    guard learnedWindows.contains(signature) else {
      return false
    }

    guard !window.isOnScreen else {
      learnedWindows.forget(signature)
      return false
    }

    return true
  }

  /// Orders the switcher's tiles and applies the `max_windows` cap.
  ///
  /// A display's windows are kept together and in `displayOrder`, and within a
  /// display a Space's windows are kept together in `spaceRanks` order, so the
  /// overlay can slice the result into sections without re-sorting. Windows with no
  /// rank — a Space nobody has visited, or no learned Spaces at all — sort last.
  ///
  /// What happens inside a group is up to `order`. `title` and `application` both
  /// put the windows on screen first, since those are the common case and the
  /// number keys should land on them, and differ only in whether a changing window
  /// title may move a tile. `stable` ignores all of it and keeps the places handed
  /// out by `sequence`.
  nonisolated static func ordered(
    _ windows: [WindowInfo],
    displayOrder: [CGDirectDisplayID],
    spaceRanks: [CGWindowID: Int] = [:],
    sequence: [CGWindowID: Int] = [:],
    order: WindowOrder = .title,
    limit: Int
  ) -> [WindowInfo] {
    let rankByDisplay = Dictionary(
      uniqueKeysWithValues: displayOrder.enumerated().map { ($0.element, $0.offset) })

    let sorted = windows.sorted { first, second in
      let firstRank = rankByDisplay[first.displayID] ?? displayOrder.count
      let secondRank = rankByDisplay[second.displayID] ?? displayOrder.count

      if firstRank != secondRank {
        return firstRank < secondRank
      }

      if first.displayID != second.displayID {
        return first.displayID < second.displayID
      }

      let firstSpace = spaceRanks[first.id] ?? Int.max
      let secondSpace = spaceRanks[second.id] ?? Int.max

      if firstSpace != secondSpace {
        return firstSpace < secondSpace
      }

      // A stable order is the whole point of `stable`: not being on screen, not
      // the title, nothing below the grouping keys may move a tile.
      if order == .stable {
        let firstPlace = sequence[first.id] ?? Int.max
        let secondPlace = sequence[second.id] ?? Int.max

        return firstPlace != secondPlace ? firstPlace < secondPlace : first.id < second.id
      }

      if first.isOnScreen != second.isOnScreen {
        return first.isOnScreen
      }

      if first.appName != second.appName {
        return first.appName.localizedStandardCompare(second.appName) == .orderedAscending
      }

      if order == .title, first.title != second.title {
        return first.title.localizedStandardCompare(second.title) == .orderedAscending
      }

      return first.id < second.id
    }

    return Array(sorted.prefix(max(0, limit)))
  }
}
