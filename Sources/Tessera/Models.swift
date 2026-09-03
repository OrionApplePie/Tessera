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
  /// Recomputed when the overlay opens, not only on a background refresh: this is
  /// the mark that says where you are, and it has to be right at that moment.
  var isActive: Bool
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

/// What the highlight can sit on: a window, or a Space with nothing on it.
///
/// A Space is a place, and an empty one is a place you can go — so the arrows have
/// to be able to reach it. Windows and empty Spaces therefore share one list, and
/// the index the overlay keeps is an index into that.
enum OverlayTarget: Identifiable {
  case window(WindowTileModel)
  case space(WindowSectionID)

  var id: String {
    switch self {
    case .window(let tile):
      return "w\(tile.id)"
    case .space(let section):
      return "s\(section.displayID)-\(section.spaceIndex ?? -1)"
    }
  }

  var window: WindowTileModel? {
    guard case .window(let tile) = self else {
      return nil
    }

    return tile
  }

  var space: WindowSectionID? {
    guard case .space(let section) = self else {
      return nil
    }

    return section
  }
}

/// The tiles of one Space of one display, as the overlay lays them out under a
/// single heading.
struct WindowTileSection: Identifiable {
  let id: WindowSectionID
  /// Empty when there is nothing worth saying: one display, one known Space.
  let title: String
  var tiles: [WindowTileModel]
  /// What the arrows can land on here: the windows, or the Space itself when it
  /// holds none.
  var targets: [OverlayTarget] {
    tiles.isEmpty ? [.space(id)] : tiles.map(OverlayTarget.window)
  }

  /// The Space showing right now, drawn so it stands out from the rest of the map.
  var isCurrent: Bool = false
  /// A Space made by a fullscreen window rather than a desktop. Marked, because it
  /// behaves differently: it holds one window and cannot hold another.
  var isFullscreen: Bool = false

  /// Takes one window off the map, keeping the place it was on.
  ///
  /// A Space with nothing left on it is an empty desktop, and the map draws it as
  /// one: closing the last window there does not make the place stop existing. Only
  /// a group standing for no Space at all — windows whose Space the window server
  /// would not name — has nothing left to be once its tiles are gone.
  static func removing(
    _ windowID: CGWindowID,
    from sections: [WindowTileSection]
  ) -> [WindowTileSection] {
    sections.compactMap { section in
      var section = section
      section.tiles.removeAll { $0.id == windowID }

      return section.tiles.isEmpty && section.id.spaceIndex == nil ? nil : section
    }
  }

  /// Splits an already ordered tile list into sections.
  ///
  /// The order is taken as given: `WindowListService` keeps a display's Spaces
  /// together and a Space's windows together, so each heading covers one
  /// contiguous run and sections never interleave.
  /// Swaps two tiles addressed by their place in the flat list.
  ///
  /// `nil` when the two do not sit in the same section. Sections are contiguous
  /// runs of one display and one Space, so a swap across one would move a
  /// thumbnail to a display it is not on — and an arrangement of thumbnails must
  /// not claim a window is somewhere it is not.
  static func swapping(
    _ first: Int,
    _ second: Int,
    in sections: [WindowTileSection]
  ) -> [WindowTileSection]? {
    guard first != second else {
      return nil
    }

    var offset = 0
    for (index, section) in sections.enumerated() {
      let range = offset..<(offset + section.tiles.count)
      offset += section.tiles.count

      guard range.contains(first), range.contains(second) else {
        continue
      }

      var swapped = sections
      swapped[index].tiles.swapAt(first - range.lowerBound, second - range.lowerBound)
      return swapped
    }

    return nil
  }

  static func sections(
    from tiles: [WindowTileModel],
    displayNames: [CGDirectDisplayID: String],
    grouping: OverlayGrouping = .displays,
    spaceCounts: [CGDirectDisplayID: Int] = [:],
    currentSpaces: [CGDirectDisplayID: Int] = [:],
    spaceNames: [WindowSectionID: String] = [:],
    fullscreenSpaces: Set<WindowSectionID> = []
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

    // A Space with nothing in it is still a place on the map, and leaving it out
    // would make the map disagree with Mission Control — and leave nowhere to put a
    // window that is being moved somewhere empty.
    if grouping.contains(.spaces), !spaceCounts.isEmpty {
      runs = withEmptySpaces(runs, spaceCounts: spaceCounts)
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
          namesSpace: grouping.contains(.spaces) && (runsPerDisplay[run.id.displayID] ?? 0) > 1,
          spaceName: spaceNames[run.id]
        ),
        tiles: run.tiles,
        isCurrent: run.id.spaceIndex != nil
          && currentSpaces[run.id.displayID] == run.id.spaceIndex,
        isFullscreen: fullscreenSpaces.contains(run.id)
      )
    }
  }

  /// Fills in a run for every Space each display has, in the system's order, so
  /// that the empty ones appear between the occupied ones rather than not at all.
  private static func withEmptySpaces(
    _ runs: [(id: WindowSectionID, tiles: [WindowTileModel])],
    spaceCounts: [CGDirectDisplayID: Int]
  ) -> [(id: WindowSectionID, tiles: [WindowTileModel])] {
    var byID: [WindowSectionID: [WindowTileModel]] = [:]
    for run in runs {
      byID[run.id, default: []].append(contentsOf: run.tiles)
    }

    var filled: [(id: WindowSectionID, tiles: [WindowTileModel])] = []

    // Displays in the order their windows appeared, then any display with Spaces
    // but nothing on them at all.
    let seen = runs.map(\.id.displayID)
    let displays = seen + spaceCounts.keys.filter { !seen.contains($0) }.sorted()

    for displayID in NSOrderedSet(array: displays.map { NSNumber(value: $0) }).compactMap({
      ($0 as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }) {
      for index in 0..<(spaceCounts[displayID] ?? 0) {
        let id = WindowSectionID(displayID: displayID, spaceIndex: index)
        filled.append((id, byID[id] ?? []))
      }
    }

    return filled.isEmpty ? runs : filled
  }

  /// The heading names only what tells this section apart from its neighbours: the
  /// display when more than one is on show, the Space when that display
  /// contributes more than one group. With a single display and a single group it
  /// says nothing, and the overlay draws no heading at all.
  private static func title(
    for id: WindowSectionID,
    displayNames: [CGDirectDisplayID: String],
    namesDisplay: Bool,
    namesSpace: Bool,
    spaceName: String? = nil
  ) -> String {
    var parts: [String] = []

    if namesDisplay {
      parts.append(displayNames[id.displayID] ?? "Display \(id.displayID)")
    }

    if namesSpace {
      parts.append(spaceName ?? id.spaceIndex.map { "Space \($0 + 1)" } ?? "Other Spaces")
    }

    // An empty part is a Space that declines to name itself — a fullscreen one — and
    // it must not leave the separator hanging behind the display's name.
    return parts.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

extension Array {
  /// The element at an index that may not exist. The overlay indexes a list that
  /// changes underneath it, and asking for a place that has gone is ordinary.
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
