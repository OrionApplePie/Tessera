import Testing

@testable import TesseraKit

@Suite("KeyboardLayouts")
struct KeyboardLayoutsTests {
  /// The key that is "v" on ABC is "м" on RussianWin, which is what makes
  /// "Мониторинг системы" reachable without switching layout.
  @Test("A key press is read as every letter its key carries")
  func collectsEveryReadingOfTheKey() {
    let readings = KeyboardLayouts.readings(typed: "v", latin: "v", onOtherLayouts: ["v", "м"])

    #expect(readings == ["v", "м"])
  }

  @Test("What was typed is tried first, then the Latin letter of the same key")
  func ordersTheReadings() {
    let readings = KeyboardLayouts.readings(typed: "м", latin: "v", onOtherLayouts: ["v", "м"])

    #expect(readings == ["м", "v"])
  }

  @Test("A key with no Latin letter still reads what the layouts make of it")
  func toleratesAMissingLatinLetter() {
    let readings = KeyboardLayouts.readings(typed: "ю", latin: nil, onOtherLayouts: ["ю", "."])

    #expect(readings == ["ю", "."])
  }

  @Test("The same letter in another case is not a second reading")
  func dropsCaseDuplicates() {
    let readings = KeyboardLayouts.readings(typed: "V", latin: "v", onOtherLayouts: ["v"])

    #expect(readings == ["V"])
  }

  @Test("One layout gives one reading")
  func keepsASingleReading() {
    let readings = KeyboardLayouts.readings(typed: "c", latin: "c", onOtherLayouts: ["c"])

    #expect(readings == ["c"])
  }
}
