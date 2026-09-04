import Foundation

/// Finds the window a tile names, among the titles Accessibility offers.
///
/// The two sources do not always spell the same window the same way. Activity
/// Monitor's window is "Мониторинг системы" to the window server, which is where
/// the tile's title comes from, and "Мониторинг системы – Все процессы" to
/// Accessibility, which is where it has to be raised. Matching on equality alone
/// therefore aimed at nothing, spent the whole retry budget, asked Apple Events,
/// and reported that the window could not be raised by any means — while the
/// application had come forward and the window was on screen, because it only had
/// the one.
enum WindowTitleMatch {
  /// Which of `candidates` is the window called `title`, if it can be told.
  ///
  /// An exact match wins outright. Failing that, a candidate that extends the
  /// title, or that the title extends, counts — but only if there is exactly one.
  /// Two documents whose names begin alike would otherwise be a coin toss, and
  /// raising the wrong window is worse than raising none: the caller reports that
  /// it could not aim, which is true, and the outcome teaches nothing about the
  /// window rather than teaching something false.
  static func index(of title: String, among candidates: [String]) -> Int? {
    guard !title.isEmpty else {
      return nil
    }

    if let exact = candidates.firstIndex(of: title) {
      return exact
    }

    let extending = candidates.indices.filter { index in
      let candidate = candidates[index]
      guard !candidate.isEmpty else {
        return false
      }

      return candidate.hasPrefix(title) || title.hasPrefix(candidate)
    }

    return extending.count == 1 ? extending[0] : nil
  }
}
