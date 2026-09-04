import Foundation

/// Finding a place on the map by typing at it.
///
/// Three things name a window, and they are not worth the same: the application it
/// belongs to, the title it carries, and the Space it is on. Someone typing "tel"
/// means Telegram, not a Finder window whose title happens to contain those letters
/// — so the application's name counts for most, the title for less, and the
/// heading over the group for least. The heading is searched at all because an
/// empty Space has nothing else to be found by, and "desktop 3" should reach it.
enum WindowSearch {
  /// A place the highlight can sit on, with the words that name it.
  struct Candidate: Equatable {
    /// Where it sits among the targets, which is what the highlight counts in.
    let index: Int
    let application: String
    let title: String
    /// The heading its group carries: the display, the desktop number, or both.
    let place: String
  }

  private static let applicationWeight = 3
  private static let titleWeight = 2
  private static let placeWeight = 1

  /// Everything on the map, in the order it is drawn.
  static func candidates(in sections: [WindowTileSection]) -> [Candidate] {
    var candidates: [Candidate] = []
    var index = 0

    for section in sections {
      guard !section.tiles.isEmpty else {
        candidates.append(
          Candidate(index: index, application: "", title: "", place: section.title))
        index += 1
        continue
      }

      for tile in section.tiles {
        candidates.append(
          Candidate(
            index: index,
            application: tile.displayAppName,
            title: tile.displayTitle,
            place: section.title
          )
        )
        index += 1
      }
    }

    return candidates
  }

  /// The best place for what has been typed, or nothing when nothing fits.
  ///
  /// `queries` are readings of the same typing — what the keys produced, and the
  /// same keys read as Latin letters — so a name in one alphabet is still found
  /// while the keyboard is in another. The best reading wins.
  ///
  /// Ties are broken by going forward from where the highlight is, which is what
  /// makes a single letter walk its own windows: press "c" again and the next
  /// window of that name is chosen rather than the same one.
  static func best(
    for queries: [String],
    among candidates: [Candidate],
    after current: Int
  ) -> Int? {
    let scored = candidates.compactMap { candidate -> (index: Int, score: Int)? in
      guard let score = score(queries, for: candidate) else {
        return nil
      }

      return (candidate.index, score)
    }

    guard let best = scored.map(\.score).max() else {
      return nil
    }

    let winners = scored.filter { $0.score == best }.map(\.index)

    return winners.first { $0 > current } ?? winners.first
  }

  private static func score(_ queries: [String], for candidate: Candidate) -> Int? {
    let fields = [
      (candidate.application, applicationWeight),
      (candidate.title, titleWeight),
      (candidate.place, placeWeight),
    ]

    var best: Int?

    for query in queries where !query.isEmpty {
      for (text, weight) in fields where !text.isEmpty {
        guard let score = FuzzyMatch.score(query, in: text) else {
          continue
        }

        best = Swift.max(best ?? Int.min, score * weight)
      }
    }

    return best
  }
}
