import AppKit
import CoreGraphics
import Foundation

/// A window discovered on screen, reduced to the Sendable facts Tessera needs.
///
/// `id` is the CoreGraphics window number. It is stable for the lifetime of the
/// window, which is what lets a thumbnail, a tile and an activation request all
/// refer to the same window without holding a non-Sendable `SCWindow`.
struct DiscoveredWindow: Identifiable, Hashable, Sendable {
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
struct WindowTile: Identifiable {
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
  /// Whether this window's application is putting sound out right now. What is
  /// playing cannot be known — macOS keeps that behind an entitlement — so this is
  /// the whole of what a tile can say about sound.
  var isSounding: Bool = false

  var displayAppName: String {
    appName.isEmpty ? "Unknown" : appName
  }

  var displayTitle: String {
    title.isEmpty ? "<untitled>" : title
  }
}

/// Identifies one heading in the overlay: a Space of a display, or a display's
/// windows whose Space is not known.
struct SpaceSectionID: Hashable {
  let displayID: CGDirectDisplayID
  let spaceIndex: Int?
}

/// What the highlight can sit on: a window, or a Space with nothing on it.
///
/// A Space is a place, and an empty one is a place you can go — so the arrows have
/// to be able to reach it. Windows and empty Spaces therefore share one list, and
/// the index the overlay keeps is an index into that.
enum OverlayTarget: Identifiable {
  case window(WindowTile)
  case space(SpaceSectionID)

  var id: String {
    switch self {
    case .window(let tile):
      return "w\(tile.id)"
    case .space(let section):
      return "s\(section.displayID)-\(section.spaceIndex ?? -1)"
    }
  }

  var window: WindowTile? {
    guard case .window(let tile) = self else {
      return nil
    }

    return tile
  }

  var space: SpaceSectionID? {
    guard case .space(let section) = self else {
      return nil
    }

    return section
  }
}

/// The tiles of one Space of one display, as the overlay lays them out under a
/// single heading.
struct SpaceSection: Identifiable {
  let id: SpaceSectionID
  /// Empty when there is nothing worth saying: one display, one known Space.
  let title: String
  var tiles: [WindowTile]
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

  /// The map cut down to a budget of cells, per display.
  ///
  /// The Space you are on is never cut: it is the one place the map has to be able
  /// to show. Beyond that the order stands, and what does not fit is left off the
  /// end — a map that keeps everything by making every tile too small to read is
  /// answering the wrong question.
  static func fitting(
    _ sections: [SpaceSection],
    cellsPerDisplay budget: Int
  ) -> [SpaceSection] {
    let budgets = Dictionary(
      uniqueKeysWithValues: Set(sections.map(\.id.displayID)).map { ($0, budget) })

    return fitting(sections, cellsByDisplay: budgets)
  }

  /// The same, with a budget of its own for each display.
  ///
  /// The displays do not always want the same amount of map: one may hold two
  /// Spaces and the other ten, and a share the busy one cannot use is better spent
  /// than left blank. What a display may draw is decided before this — in whole
  /// rows of the grid — and this only holds the map to it.
  ///
  /// The Space you are on is taken out of the budget before anything else rather
  /// than added on top of it: kept as an extra it made a band of five into a band
  /// of six, which is a second row, and a budget counted in rows that quietly draws
  /// one more is not a budget.
  static func fitting(
    _ sections: [SpaceSection],
    cellsByDisplay budgets: [CGDirectDisplayID: Int]
  ) -> [SpaceSection] {
    var spent: [CGDirectDisplayID: Int] = [:]

    for section in sections where section.isCurrent {
      spent[section.id.displayID, default: 0] += 1
    }

    return sections.filter { section in
      guard !section.isCurrent else {
        return true
      }

      let cost = 1
      let already = spent[section.id.displayID] ?? 0

      guard already + cost <= budgets[section.id.displayID] ?? 0 else {
        return false
      }

      spent[section.id.displayID] = already + cost

      return true
    }
  }

  /// What the map would draw, in a form cheap to compare.
  ///
  /// The list is rebuilt several times a second — the refresh loop, a Space change,
  /// every thumbnail as it arrives — and each rebuilt list that reaches the view
  /// redraws every tile, pictures and all. Most of those rebuilds are identical to
  /// what is already on screen, and this is how they are recognised: everything the
  /// drawing depends on goes in, and nothing else does, so a rebuild that changes
  /// nothing changes no pixels either.
  static func signature(of sections: [SpaceSection]) -> Int {
    var hasher = Hasher()

    for section in sections {
      hasher.combine(section.id.displayID)
      hasher.combine(section.id.spaceIndex)
      hasher.combine(section.title)
      hasher.combine(section.isCurrent)
      hasher.combine(section.isFullscreen)

      for tile in section.tiles {
        hasher.combine(tile.id)
        hasher.combine(tile.appName)
        hasher.combine(tile.title)
        hasher.combine(tile.isActive)
        hasher.combine(tile.isMinimized)
        hasher.combine(tile.isSounding)
        hasher.combine(tile.isThumbnailStale)
        // The picture itself by identity: a new capture is a new object, and that is
        // exactly when the tile has to be drawn again.
        hasher.combine(tile.thumbnail.map { UInt(bitPattern: ObjectIdentifier($0).hashValue) })
      }
    }

    return hasher.finalize()
  }

  /// Takes one window off the map, keeping the place it was on.
  ///
  /// A Space with nothing left on it is an empty desktop, and the map draws it as
  /// one: closing the last window there does not make the place stop existing. Only
  /// a group standing for no Space at all — windows whose Space the window server
  /// would not name — has nothing left to be once its tiles are gone.
  static func removing(
    _ windowID: CGWindowID,
    from sections: [SpaceSection]
  ) -> [SpaceSection] {
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
    in sections: [SpaceSection]
  ) -> [SpaceSection]? {
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
    from tiles: [WindowTile],
    displayNames: [CGDirectDisplayID: String],
    grouping: OverlayGrouping = .displays,
    spaceCounts: [CGDirectDisplayID: Int] = [:],
    displayOrder: [CGDirectDisplayID] = [],
    currentSpaces: [CGDirectDisplayID: Int] = [:],
    spaceNames: [SpaceSectionID: String] = [:],
    fullscreenSpaces: Set<SpaceSectionID> = []
  ) -> [SpaceSection] {
    guard !grouping.isEmpty else {
      guard let first = tiles.first else {
        return []
      }

      return [
        SpaceSection(
          id: SpaceSectionID(displayID: first.displayID, spaceIndex: first.spaceIndex),
          title: "",
          tiles: tiles
        )
      ]
    }

    var runs: [(id: SpaceSectionID, tiles: [WindowTile])] = []

    for tile in tiles {
      // A Space belongs to one display, so splitting by Space splits by display
      // whether or not the heading says so.
      let id = SpaceSectionID(
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
      runs = withEmptySpaces(runs, spaceCounts: spaceCounts, displayOrder: displayOrder)
    }

    let displays = Set(runs.map(\.id.displayID))
    let runsPerDisplay = runs.reduce(into: [CGDirectDisplayID: Int]()) { counts, run in
      counts[run.id.displayID, default: 0] += 1
    }

    return runs.map { run in
      SpaceSection(
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
    _ runs: [(id: SpaceSectionID, tiles: [WindowTile])],
    spaceCounts: [CGDirectDisplayID: Int],
    displayOrder: [CGDirectDisplayID]
  ) -> [(id: SpaceSectionID, tiles: [WindowTile])] {
    var byID: [SpaceSectionID: [WindowTile]] = [:]
    for run in runs {
      byID[run.id, default: []].append(contentsOf: run.tiles)
    }

    var filled: [(id: SpaceSectionID, tiles: [WindowTile])] = []

    // The displays as they are actually arranged, so a monitor standing above the
    // laptop is drawn above it whether or not anything is open on it. Ordered by
    // where their windows came in, a display with no windows at all could only be
    // appended, which put an empty screen standing highest at the foot of the map.
    // A display the arrangement does not name keeps the place its windows gave it.
    var displays: [CGDirectDisplayID] = []
    for displayID in displayOrder + runs.map(\.id.displayID) + spaceCounts.keys.sorted()
    where !displays.contains(displayID) {
      displays.append(displayID)
    }

    for displayID in displays {
      for index in 0..<(spaceCounts[displayID] ?? 0) {
        let id = SpaceSectionID(displayID: displayID, spaceIndex: index)
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
    for id: SpaceSectionID,
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
    let named = parts.filter { !$0.isEmpty }

    // With only one display there is no name to hang it behind either, and the
    // heading came out empty: no frame, no fullscreen mark, and no heading to tap
    // the Space into view. Unplugging a display is enough to get there, since its
    // fullscreen Spaces move to the one that is left. It says what it is instead.
    guard !named.isEmpty else {
      return namesSpace ? localized("Fullscreen") : ""
    }

    return named.joined(separator: " · ")
  }
}

extension Array {
  /// The element at an index that may not exist. The overlay indexes a list that
  /// changes underneath it, and asking for a place that has gone is ordinary.
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
