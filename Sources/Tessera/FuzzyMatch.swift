import Foundation

/// How well a typed query fits a piece of text, in the register `fzf` and the
/// editors' file-openers established: every letter of the query has to appear in
/// order, and what separates a good match from an incidental one is *where* the
/// letters landed.
///
/// Scored rather than filtered, because a switcher's list is short and the answer
/// has to be the best window, not every window that technically contains the
/// letters. "tg" should find Telegram over "Settings — Downloads", and it does that
/// on bonuses: the start of a word is worth more than the middle of one, letters
/// running together are worth more than letters scattered, and the start of the
/// text is worth most.
///
/// Deliberately small. A window list is a few dozen strings of a few dozen
/// characters, so the table below is cheap and the subtleties `fzf` needs for a
/// million paths — normalisation, ranges, case bonuses — are left out.
enum FuzzyMatch {
  /// A letter landing where a letter matters.
  private static let match = 16
  /// The first letter of a word, which is where the eye goes.
  private static let boundary = 8
  /// A run of letters, which is what typing a name actually looks like.
  private static let consecutive = 8
  /// The start of the text: what someone typing a name expects to be typing.
  private static let firstCharacter = 16
  private static let gapStart = -3
  private static let gapExtension = -1
  /// What ends a word, so that the letter after it starts one.
  private static let separators: Set<Character> = [
    " ", "-", "_", ".", "/", "·", ":", ",", "(", "[", "—",
  ]

  /// The score of the best way the query fits, or `nil` when it does not fit at
  /// all.
  ///
  /// A empty query fits everything equally and says so with zero, so a caller can
  /// tell "nothing typed" from "nothing matched".
  static func score(_ query: String, in text: String) -> Int? {
    let needle = Array(query.lowercased())
    let haystack = Array(text.lowercased())
    let original = Array(text)

    guard !needle.isEmpty else {
      return 0
    }

    guard needle.count <= haystack.count else {
      return nil
    }

    // best[position] is the score of matching everything typed so far, with the
    // last letter landing exactly here. Carried forward one query letter at a time,
    // which is what makes a run of letters worth more than the same letters apart.
    var best = [Int?](repeating: nil, count: haystack.count)
    var previous = [Int?](repeating: nil, count: haystack.count)

    for (step, letter) in needle.enumerated() {
      previous = best
      best = [Int?](repeating: nil, count: haystack.count)

      for position in haystack.indices where haystack[position] == letter {
        let placement = bonus(at: position, in: haystack, original: original)

        if step == 0 {
          best[position] =
            match + placement + (position == 0 ? firstCharacter : 0)
            + gapStart + gapExtension * position
          continue
        }

        // Either the letter before this one landed right here — a run — or it
        // landed further back, and the gap between them costs.
        var candidate: Int?

        if position > 0, let run = previous[position - 1] {
          candidate = run + match + max(placement, consecutive)
        }

        for earlier in stride(from: position - 2, through: 0, by: -1) {
          guard let broken = previous[earlier] else {
            continue
          }

          let gap = gapStart + gapExtension * (position - earlier - 1)
          candidate = Swift.max(candidate ?? Int.min, broken + match + placement + gap)
        }

        best[position] = candidate
      }
    }

    return best.compactMap { $0 }.max()
  }

  /// What a position is worth before anything is typed: the first letter of a word
  /// or of a camelCase hump is where a name is read from.
  private static func bonus(at position: Int, in text: [Character], original: [Character]) -> Int {
    guard position > 0 else {
      return boundary
    }

    let before = text[position - 1]

    if separators.contains(before) {
      return boundary
    }

    // A capital after a small letter starts a word as surely as a space does, and
    // it is the only word break some application names have.
    if original[position].isUppercase, original[position - 1].isLowercase {
      return boundary
    }

    return 0
  }
}
