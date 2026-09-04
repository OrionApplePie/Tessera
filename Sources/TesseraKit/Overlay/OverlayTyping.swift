import AppKit
import Foundation

// MARK: - Choosing by number

extension OverlayWindowController {
  /// Chooses what a number key points at, counted the way the map is counted.
  ///
  /// A digit means the tile a person can see, and with the windows of a Space drawn
  /// as one card that is not the same as the window behind it: eleven Finder
  /// windows are one tile and eleven places the highlight can sit. Counted in
  /// places, "6" reached the second Finder window while the sixth tile was an empty
  /// desktop — a switch to a Space nobody asked for, and, for a window
  /// Accessibility will not aim at, an application's Window menu opening on screen
  /// to raise it.
  func selectCell(_ cell: Int) {
    var target = 0
    var cells = 0

    for section in windowCoordinator.sections {
      let drawn = section.cells(whenStacked: config.overlayDeck == .stack)

      if cells + drawn > cell {
        selectWindow(at: target + (cell - cells))
        return
      }

      cells += drawn
      target += section.targets.count
    }
  }
}

// MARK: - Typing

/// Finding a window by typing at the map, in either of the two ways the
/// configuration allows.
extension OverlayWindowController {
  /// Takes a typed character and moves the highlight to whatever it now names.
  ///
  /// The same key pressed twice does not become a two-letter query: a single letter
  /// is how a person walks the windows of one application, and taking that away to
  /// gain "cc" would be a poor trade. Anything longer is a search.
  func type(_ character: Character, latin: Character?, readings: [Character]) {
    guard config.overlaySearch == .fuzzy else {
      jumpToName(readings)
      return
    }

    let typed = selection.query
    let repeated = typed.count == 1 && typed.first?.lowercased() == character.lowercased()

    if !repeated {
      selection.query.append(character)
      latinQuery.append(latin ?? character)
    }

    guard
      let match = WindowSearch.best(
        for: [selection.query, latinQuery],
        among: WindowSearch.candidates(in: windowCoordinator.sections),
        after: selection.index
      )
    else {
      logger.debug("Nothing on the map answers to \(selection.query)")
      return
    }

    selection.index = match
    logger.debug("Search \(selection.query) landed on index \(match)")
  }

  /// The older way of finding a window: one letter, and the next thing that letter
  /// names.
  ///
  /// Four passes, in the order a letter usually means them: the application's whole
  /// name, a word inside it, the window's whole title, a word inside that. So "e"
  /// goes to Excel before it goes to a window whose title has a word starting with
  /// e — and it does reach that window, on the next press, because pressing the
  /// letter again walks everything it names rather than only the pass that answered
  /// first. Stopping at the first pass left the second line of a tile — the file, the
  /// tab, the document — unreachable whenever some application happened to share the
  /// letter.
  ///
  /// The field still decides before the reading does. Tried the other way round, a
  /// Russian reading of the key matched some window's title before the Latin one
  /// ever reached the applications, and with Russian titles on screen it usually
  /// found one — which is what made the letters look like they were confused.
  func jumpToName(_ readings: [Character]) {
    let targets = windowCoordinator.targets
    let passes: [(OverlayGrid.MatchField, OverlayGrid.MatchScope)] = [
      (.applicationName, .wholeName),
      (.applicationName, .anyWord),
      (.windowTitle, .wholeName),
      (.windowTitle, .anyWord),
    ]

    var ranked: [Int] = []

    for (field, scope) in passes {
      for character in readings {
        for match in OverlayGrid.matches(
          for: character, in: targets, field: field, scope: scope)
        where !ranked.contains(match) {
          ranked.append(match)
        }
      }
    }

    guard !ranked.isEmpty else {
      return
    }

    // Standing on something the letter names means the letter is being pressed
    // again, so the map's own order takes over from the ranking and the next one
    // along is chosen. Otherwise the best-ranked match wins, whichever way it sits.
    let match =
      ranked.contains(selection.index)
      ? (ranked.sorted().first { $0 > selection.index } ?? ranked.sorted()[0])
      : ranked[0]

    selection.index = match
    logger.debug("Jumped to index \(match) of \(ranked.count) the letter names")
  }

  /// Backspace: the last character typed is taken back, and the highlight goes to
  /// what the shorter query names — without moving on, so deleting a letter does
  /// not walk the list.
  func untype() {
    guard !selection.query.isEmpty else {
      return
    }

    selection.query.removeLast()
    latinQuery = String(latinQuery.dropLast())

    guard !selection.query.isEmpty,
      let match = WindowSearch.best(
        for: [selection.query, latinQuery],
        among: WindowSearch.candidates(in: windowCoordinator.sections),
        after: -1
      )
    else {
      return
    }

    selection.index = match
  }
}
