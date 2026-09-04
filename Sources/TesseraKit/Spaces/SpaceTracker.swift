import CoreGraphics
import Foundation

/// Learns which windows share a Space by watching which of them are on screen together.
///
/// macOS exposes no public API for Space membership: `NSWorkspace` will say that
/// the active Space changed, never which one it is, and `SCWindow` only knows
/// whether a window is on screen right now. What is observable is that every
/// window on screen at one moment shares one Space per display — so a snapshot is
/// a membership set for whichever Space is active, and repeated snapshots build up
/// a partition of the windows.
///
/// The limits are inherent to the approach rather than gaps to be filled later:
///
/// - Spaces are numbered in the order they were first seen, which need not match
///   the order Mission Control shows them in.
/// - A Space nobody visited while Tessera was running is unknown, and so are the
///   windows sitting on it.
/// - A minimized window is on no Space as far as this can tell, because it is
///   never on screen.
struct SpaceTracker {
  private struct LearnedSpace {
    var members: Set<CGWindowID>
  }

  private var spacesByDisplay: [CGDirectDisplayID: [LearnedSpace]] = [:]

  /// Records that these windows were on screen together, and so share the active
  /// Space of that display.
  mutating func observe(onScreen windowIDs: Set<CGWindowID>, on displayID: CGDirectDisplayID) {
    guard !windowIDs.isEmpty else {
      return
    }

    var spaces = spacesByDisplay[displayID] ?? []
    let target = matchingSpace(in: spaces, for: windowIDs) ?? spaces.count

    if target == spaces.count {
      spaces.append(LearnedSpace(members: windowIDs))
    } else {
      // The Space is what is on screen now, not what it used to hold: windows that
      // have since closed or moved away are gone from it.
      spaces[target].members = windowIDs
    }

    // A window is on exactly one Space, so seeing it here takes it off every other.
    for index in spaces.indices where index != target {
      spaces[index].members.subtract(windowIDs)
    }

    spacesByDisplay[displayID] = spaces
  }

  /// Forgets windows that have closed, so a long session does not accumulate them.
  mutating func retain(windowIDs: Set<CGWindowID>) {
    for (displayID, spaces) in spacesByDisplay {
      spacesByDisplay[displayID] = spaces.map { space in
        var space = space
        space.members.formIntersection(windowIDs)
        return space
      }
    }
  }

  /// Which Space a window is on, numbered from zero in the order Spaces were first
  /// seen. `nil` while the window's Space has never been looked at.
  func spaceIndex(of windowID: CGWindowID, on displayID: CGDirectDisplayID) -> Int? {
    spacesByDisplay[displayID]?.firstIndex { $0.members.contains(windowID) }
  }

  /// How many Spaces a display is known to have. Emptied Spaces still count, so
  /// that closing every window on Space 1 does not renumber Space 2.
  func knownSpaceCount(on displayID: CGDirectDisplayID) -> Int {
    spacesByDisplay[displayID]?.count ?? 0
  }

  /// The Space sharing the most windows with what is on screen is the one being
  /// looked at. Anything else is a different Space that has gained or lost windows
  /// since it was last seen. On a tie the Space seen first wins, so the numbering
  /// stays put.
  private func matchingSpace(in spaces: [LearnedSpace], for windowIDs: Set<CGWindowID>) -> Int? {
    var best: (index: Int, shared: Int)?

    for (index, space) in spaces.enumerated() {
      let shared = space.members.intersection(windowIDs).count
      guard shared > 0, shared > (best?.shared ?? 0) else {
        continue
      }

      best = (index, shared)
    }

    return best?.index
  }
}
