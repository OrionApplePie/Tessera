import Foundation

/// The switcher's own words, looked up where they actually live.
///
/// Three things have to be got right, and all three fail the same way — by handing
/// back the key, which is English and therefore looks like a translation nobody
/// needed. Each was measured failing before it was fixed.
///
/// **Which bundle.** A package's strings are not in `Bundle.main`: a plain
/// executable has no bundle of its own to keep them in, and SwiftUI's `Text("…")`
/// and a bare `String(localized:)` both look there.
///
/// **Which folder inside it.** SwiftPM puts the `.lproj` folders at the root of its
/// resource bundle and leaves an empty `Resources` folder beside them; Foundation
/// sees that folder, decides the bundle keeps its resources there, and looks for
/// the tables in the empty copies. Measured: `Bundle.module.localizedString(forKey:
/// "Cancel")` answered `Cancel` with `Отмена` sitting in
/// `ru.lproj/Localizable.strings` two directories away.
///
/// **Which language.** `Bundle.preferredLocalizations(from:)` answered `["en"]` for
/// a process whose `Locale.preferredLanguages` began with `ru-RU`, offered a bundle
/// holding both — a process with no bundle of its own has no language of its own
/// either, as far as that call is concerned. So the match is made here.
private let words: Bundle = {
  let module = Bundle.module

  guard let chosen = language(preferring: Locale.preferredLanguages, among: module.localizations)
  else {
    return module
  }

  let folder = module.bundleURL.appendingPathComponent("\(chosen).lproj")

  guard FileManager.default.fileExists(atPath: folder.path), let table = Bundle(url: folder) else {
    return module
  }

  return table
}()

/// Which of the languages on hand answers what the person asked for.
///
/// Regions are ignored on purpose: someone who asked for `ru-RU` is asking for
/// Russian, and there is one Russian here. The order is theirs, so a second choice
/// only wins when the first is not translated at all.
func language(preferring wanted: [String], among available: [String]) -> String? {
  for tag in wanted {
    let code = String(tag.prefix { $0 != "-" && $0 != "_" })

    if let match = available.first(where: { $0 == tag || $0 == code }) {
      return match
    }
  }

  return nil
}

/// One of the switcher's words, in the language the system asked for.
///
/// The table is asked directly rather than through `String(localized:bundle:)`,
/// which looks for a `.lproj` folder *inside* the bundle it is given and finds none
/// inside a `.lproj` folder — another way of quietly answering with the key.
/// Anything with a number or a name in it therefore arrives as a format, which is
/// what the tables hold anyway.
func localized(_ key: String) -> String {
  words.localizedString(forKey: key, value: nil, table: nil)
}

/// The same, with the pieces that are not words filled in.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
  String(format: words.localizedString(forKey: key, value: nil, table: nil), arguments: arguments)
}

/// What the choice above came out as, for the log at startup: a switcher speaking
/// the wrong language is a thing people report, and this is the first question.
var chosenLanguage: String {
  "asked=\(Locale.preferredLanguages) available=\(Bundle.module.localizations.sorted()) "
    + "using=\(words.bundleURL.lastPathComponent)"
}
