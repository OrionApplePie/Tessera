import Foundation
import Testing

@testable import TesseraKit

@Suite("The words the switcher says")
struct LocalizedTests {
  /// The tables have to be *reachable*, which is a different thing from existing.
  /// Every way this can go wrong ends with the key being shown — and the keys are
  /// English, so a broken lookup looks exactly like a translation nobody needed.
  @Test("Both languages are in the module's own bundle")
  func carriesBothLanguages() {
    let languages = Set(Bundle.module.localizations)

    #expect(languages.contains("en"))
    #expect(languages.contains("ru"))
  }

  @Test("A word looked up in Russian comes back in Russian")
  func findsTheRussianTable() {
    #expect(table("ru")?.localizedString(forKey: "Cancel", value: nil, table: nil) == "Отмена")
  }

  /// The interpolated ones are where a table quietly stops matching the code: what
  /// the file holds is the format, not the sentence in the source.
  @Test("A key with a number in it is found too")
  func findsAnInterpolatedKey() {
    let format = table("ru")?.localizedString(forKey: "Desktop %lld", value: nil, table: nil)

    #expect(format == "Рабочий стол %lld")
    #expect(String(format: format ?? "", 4) == "Рабочий стол 4")
  }

  @Test("English is still English")
  func keepsEnglishAsItIs() {
    #expect(table("en")?.localizedString(forKey: "Cancel", value: nil, table: nil) == "Cancel")
  }

  /// The two files are generated from the sources together. This is what catches a
  /// string added by hand to one of them, or added to the code and to neither.
  @Test("The two tables hold the same keys")
  func tablesAgree() {
    let english = keys(of: "en")

    #expect(english.count > 100)
    #expect(english == keys(of: "ru"))
  }

  /// Nothing is left untranslated by accident: a Russian value equal to its English
  /// key is either a word that is the same in both — a shortcut, a product name —
  /// or a translation that was forgotten. The list of the former is short enough to
  /// write down, so the latter cannot hide in it.
  @Test("Everything is translated, or is a word that does not change")
  func translatesEverythingElse() {
    let unchanged: Set<String> = [
      "Esc", "Mission Control", "Return, Space", "Tab, ⇧ + Tab", "Tessera", "cmd+w",
      "ctrl+alt+space", "1 – 9", "⌘ + Delete", "⌘ + F", "⌘ + N", "⌘ + Return", "⌘ + [",
      "⌘ + \\", "⌘ + ]", "AmneziaVPN, Some Tray App",
    ]

    let english = strings(of: "en")
    let russian = strings(of: "ru")
    let same = english.keys.filter { english[$0] == russian[$0] }

    #expect(Set(same).subtracting(unchanged).isEmpty)
  }

  /// Regions are ignored: someone asking for `ru-RU` is asking for Russian, and
  /// there is one Russian here. Measured on this machine, `Bundle`'s own answer for
  /// exactly this question was "en", which is why the choice is made in the code.
  @Test("A regional language finds the language it belongs to")
  func matchesARegionalTag() {
    #expect(language(preferring: ["ru-RU", "en-RU"], among: ["en", "ru"]) == "ru")
    #expect(language(preferring: ["en-GB"], among: ["en", "ru"]) == "en")
  }

  /// A language nobody translated falls through to the next one asked for, and to
  /// nothing when none of them is here — where the caller keeps the module's own
  /// English rather than guessing.
  @Test("An untranslated language falls through")
  func fallsThroughToTheNextChoice() {
    #expect(language(preferring: ["fr-FR", "ru"], among: ["en", "ru"]) == "ru")
    #expect(language(preferring: ["fr", "de"], among: ["en", "ru"]) == nil)
    #expect(language(preferring: [], among: ["en", "ru"]) == nil)
  }

  private func table(_ language: String) -> Bundle? {
    Bundle(url: Bundle.module.bundleURL.appendingPathComponent("\(language).lproj"))
  }

  private func strings(of language: String) -> [String: String] {
    guard
      let file = table(language)?.bundleURL.appendingPathComponent("Localizable.strings"),
      let contents = NSDictionary(contentsOf: file) as? [String: String]
    else {
      return [:]
    }

    return contents
  }

  private func keys(of language: String) -> Set<String> {
    Set(strings(of: language).keys)
  }
}
