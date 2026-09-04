import Testing

@testable import TesseraKit

@Suite("FuzzyMatch")
struct FuzzyMatchTests {
  @Test("A query that is not there does not match")
  func rejectsWhatIsNotThere() {
    #expect(FuzzyMatch.score("zx", in: "Telegram") == nil)
    #expect(FuzzyMatch.score("mt", in: "Telegram") == nil, "the order matters")
    #expect(FuzzyMatch.score("telegramm", in: "Telegram") == nil)
  }

  @Test("Nothing typed fits everything")
  func anEmptyQueryFitsAnything() {
    #expect(FuzzyMatch.score("", in: "Telegram") == 0)
  }

  @Test("Letters are found whatever their case")
  func ignoresCase() {
    #expect(FuzzyMatch.score("TEL", in: "Telegram") != nil)
    #expect(FuzzyMatch.score("tel", in: "TELEGRAM") != nil)
  }

  /// The point of scoring rather than filtering: several windows contain the
  /// letters, and the one whose name starts with them is the one meant.
  @Test("The start of a name beats the middle of one")
  func prefersTheStart() {
    let start = FuzzyMatch.score("tel", in: "Telegram")
    let middle = FuzzyMatch.score("tel", in: "Untelegraphed")

    #expect(start != nil)
    #expect(middle != nil)
    #expect((start ?? 0) > (middle ?? 0))
  }

  /// Initials are how people name applications to themselves: "gc" is Google
  /// Chrome, not "Logic".
  @Test("The starts of words beat letters inside them")
  func prefersWordBoundaries() {
    let initials = FuzzyMatch.score("gc", in: "Google Chrome")
    let inside = FuzzyMatch.score("gc", in: "Logic")

    #expect((initials ?? 0) > (inside ?? 0))
  }

  @Test("A capital in the middle of a name starts a word too")
  func readsCamelCase() {
    let camel = FuzzyMatch.score("te", in: "TextEdit")
    let scattered = FuzzyMatch.score("te", in: "Tessera the")

    #expect(camel != nil)
    #expect(scattered != nil)
  }

  /// Typing a name looks like a run of letters, so a run is worth more than the
  /// same letters spread across the text.
  @Test("Letters running together beat letters scattered")
  func prefersConsecutiveLetters() {
    let together = FuzzyMatch.score("code", in: "Code")
    let apart = FuzzyMatch.score("code", in: "Chrome of documents everywhere")

    #expect((together ?? 0) > (apart ?? 0))
  }

  @Test("A query longer than the text cannot fit in it")
  func rejectsALongerQuery() {
    #expect(FuzzyMatch.score("telegram", in: "tel") == nil)
  }
}
