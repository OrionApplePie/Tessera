import AppKit
import CoreGraphics
import Foundation

/// A window discovered on screen, reduced to the Sendable facts Tessera needs.
///
/// `id` is the CoreGraphics window number. It is stable for the lifetime of the
/// window, which is what lets a thumbnail, a tile and an activation request all
/// refer to the same window without holding a non-Sendable `SCWindow`.
struct WindowInfo: Identifiable, Hashable, Sendable {
  let id: CGWindowID
  let appName: String
  let title: String
  let processID: pid_t
  let frame: CGRect
  /// False for a window on another Space or a minimized one: still switchable,
  /// but reaching it costs a Space switch or an unminimize.
  let isOnScreen: Bool
  /// Sitting in the Dock. Never on screen, has no surface to capture, and needs
  /// restoring before it can be raised.
  let isMinimized: Bool
  /// The display covering most of the window. A window that overlaps no display at
  /// all — one dragged entirely off the canvas — is filed under the main display
  /// rather than dropped, because it is still switchable.
  let displayID: CGDirectDisplayID
}

/// One tile in the overlay: a window plus whatever preview we managed to capture.
struct WindowTileModel: Identifiable {
  let id: CGWindowID
  let appName: String
  let title: String
  let processID: pid_t
  let isActive: Bool
  let isMinimized: Bool
  let displayID: CGDirectDisplayID
  /// Which Space of that display, as far as `SpaceTracker` has learned. `nil` for a
  /// minimized window, or one on a Space nobody has visited yet.
  let spaceIndex: Int?
  /// Shown when there is no thumbnail: a minimized window has no surface to
  /// capture, and on macOS 13 nothing does.
  let icon: NSImage?
  var thumbnail: CGImage?
  var isThumbnailStale: Bool

  var displayAppName: String {
    appName.isEmpty ? "Unknown" : appName
  }

  var displayTitle: String {
    title.isEmpty ? "<untitled>" : title
  }
}

/// Identifies one heading in the overlay: a Space of a display, or a display's
/// windows whose Space is not known.
struct WindowSectionID: Hashable {
  let displayID: CGDirectDisplayID
  let spaceIndex: Int?
}

/// The tiles of one Space of one display, as the overlay lays them out under a
/// single heading.
struct WindowTileSection: Identifiable {
  let id: WindowSectionID
  /// Empty when there is nothing worth saying: one display, one known Space.
  let title: String
  let tiles: [WindowTileModel]

  /// Splits an already ordered tile list into sections.
  ///
  /// The order is taken as given: `WindowListService` keeps a display's Spaces
  /// together and a Space's windows together, so each heading covers one
  /// contiguous run and sections never interleave.
  static func sections(
    from tiles: [WindowTileModel],
    displayNames: [CGDirectDisplayID: String],
    grouping: OverlayGrouping = .displays
  ) -> [WindowTileSection] {
    guard !grouping.isEmpty else {
      guard let first = tiles.first else {
        return []
      }

      return [
        WindowTileSection(
          id: WindowSectionID(displayID: first.displayID, spaceIndex: first.spaceIndex),
          title: "",
          tiles: tiles
        )
      ]
    }

    var runs: [(id: WindowSectionID, tiles: [WindowTileModel])] = []

    for tile in tiles {
      // A Space belongs to one display, so splitting by Space splits by display
      // whether or not the heading says so.
      let id = WindowSectionID(
        displayID: tile.displayID,
        spaceIndex: grouping.contains(.spaces) ? tile.spaceIndex : nil
      )

      if var last = runs.last, last.id == id {
        last.tiles.append(tile)
        runs[runs.count - 1] = last
        continue
      }

      runs.append((id, [tile]))
    }

    let displays = Set(runs.map(\.id.displayID))
    let runsPerDisplay = runs.reduce(into: [CGDirectDisplayID: Int]()) { counts, run in
      counts[run.id.displayID, default: 0] += 1
    }

    return runs.map { run in
      WindowTileSection(
        id: run.id,
        title: title(
          for: run.id,
          displayNames: displayNames,
          namesDisplay: grouping.contains(.displays) && displays.count > 1,
          namesSpace: grouping.contains(.spaces) && (runsPerDisplay[run.id.displayID] ?? 0) > 1
        ),
        tiles: run.tiles
      )
    }
  }

  /// The heading names only what tells this section apart from its neighbours: the
  /// display when more than one is on show, the Space when that display
  /// contributes more than one group. With a single display and a single group it
  /// says nothing, and the overlay draws no heading at all.
  private static func title(
    for id: WindowSectionID,
    displayNames: [CGDirectDisplayID: String],
    namesDisplay: Bool,
    namesSpace: Bool
  ) -> String {
    var parts: [String] = []

    if namesDisplay {
      parts.append(displayNames[id.displayID] ?? "Display \(id.displayID)")
    }

    if namesSpace {
      parts.append(id.spaceIndex.map { "Space \($0 + 1)" } ?? "Other Spaces")
    }

    return parts.joined(separator: " · ")
  }
}
