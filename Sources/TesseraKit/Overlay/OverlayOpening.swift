import AppKit

// MARK: - Where the highlight lands

/// Placing the highlight when the map goes up, and again when the list that was
/// still being read arrives behind it.
extension OverlayWindowController {
  /// The empty Space you are standing on, when that is what the map opened over.
  /// On a Space of its own it decides both where the highlight starts and how the
  /// map is drawn.
  func standingSpace() -> SpaceSectionID? {
    let display = DisplayInfo.displayID(of: screenInFront)
    let here = windowCoordinator.sections.first { $0.isCurrent && $0.id.displayID == display }

    return here?.tiles.isEmpty == true ? here?.id : nil
  }

  /// Puts the highlight back where opening the map would have put it, now that the
  /// fresh list is in.
  ///
  /// Only if it has not been moved since: the map is up while this happens, and
  /// yanking the highlight out from under a hand already stepping through it would
  /// be worse than leaving it on a tile chosen a moment ago.
  func replaceTheHighlightIfUntouched() {
    guard isOverlayVisible, selection.index == presentedIndex else {
      return
    }

    let standing = standingSpace()
    let index = OverlayGrid.initialIndex(
      for: windowCoordinator.targets, standingOn: standing)

    selection.index = index
    presentedIndex = index
  }

}
