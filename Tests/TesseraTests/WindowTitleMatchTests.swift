import Testing

@testable import Tessera

@Suite("WindowTitleMatch")
struct WindowTitleMatchTests {
  @Test("A title Accessibility spells the same way is matched outright")
  func matchesAnIdenticalTitle() {
    let candidates = ["Привет 1212.txt", "Без названия.txt"]

    #expect(WindowTitleMatch.index(of: "Без названия.txt", among: candidates) == 1)
  }

  /// The window server and Accessibility disagree about this one, measured on
  /// macOS 26: the tile says "Мониторинг системы", Accessibility says
  /// "Мониторинг системы – Все процессы".
  @Test("A title Accessibility extends is still the same window")
  func matchesATitleAccessibilityExtends() {
    let candidates = ["Мониторинг системы – Все процессы"]

    #expect(WindowTitleMatch.index(of: "Мониторинг системы", among: candidates) == 0)
  }

  @Test("A title that extends what Accessibility lists is the same window too")
  func matchesATitleThatExtendsTheCandidate() {
    let candidates = ["Отчёт"]

    #expect(WindowTitleMatch.index(of: "Отчёт — черновик", among: candidates) == 0)
  }

  @Test("An exact match wins over one that merely begins alike")
  func prefersTheExactMatch() {
    let candidates = ["Отчёт — черновик", "Отчёт"]

    #expect(WindowTitleMatch.index(of: "Отчёт", among: candidates) == 1)
  }

  @Test("Two windows beginning alike are a coin toss, so neither is raised")
  func refusesToGuessBetweenTwoCandidates() {
    let candidates = ["Отчёт за март", "Отчёт за апрель"]

    #expect(WindowTitleMatch.index(of: "Отчёт", among: candidates) == nil)
  }

  @Test("A window without a title does not match everything asked for")
  func ignoresUntitledWindows() {
    let candidates = ["", ""]

    #expect(WindowTitleMatch.index(of: "Мониторинг системы", among: candidates) == nil)
  }

  @Test("A tile without a title matches nothing")
  func matchesNothingForAnEmptyTitle() {
    #expect(WindowTitleMatch.index(of: "", among: ["Мониторинг системы"]) == nil)
  }

  @Test("A title nothing resembles matches nothing")
  func matchesNothingUnrelated() {
    #expect(WindowTitleMatch.index(of: "Telegram", among: ["Мониторинг системы"]) == nil)
  }
}
