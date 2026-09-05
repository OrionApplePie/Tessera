import AppKit
import Foundation

// MARK: - Playing

/// Play, pause and step, for a window whose application is making a sound.
extension OverlayWindowController {
  /// Sends a media key, if the highlight is on something that is playing.
  ///
  /// Refused otherwise, and said so: the key is a system-wide event that macOS
  /// routes to whatever it considers the application that is playing, so pressing
  /// it at a silent window would pause something else — a window somewhere the
  /// person is not looking at. When the highlighted application is the one making
  /// the sound, which is the case this exists for, the two are the same thing.
  func control(_ command: MediaKeys.Command) {
    guard let tile = windowCoordinator.targets[safe: selection.index]?.window else {
      return
    }

    guard tile.isSounding else {
      logger.info("\(tile.displayAppName) is not playing anything, so the media key is not sent")
      return
    }

    let sent = MediaKeys.send(command)
    logger.info("Media key for \(tile.displayAppName): sent=\(sent)")
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
