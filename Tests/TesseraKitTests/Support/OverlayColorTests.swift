import Testing

@testable import TesseraKit

@Suite("OverlayColor")
struct OverlayColorTests {
  @Test("Six digits are red, green and blue, fully opaque")
  func parsesSixDigits() throws {
    let color = try OverlayColor(parsing: "#FF8000")

    #expect(color.red == 1)
    #expect(abs(color.green - 128.0 / 255.0) < 0.0001)
    #expect(color.blue == 0)
    #expect(color.alpha == 1)
  }

  @Test("Eight digits carry the alpha channel")
  func parsesEightDigits() throws {
    let color = try OverlayColor(parsing: "#00000080")

    #expect(color.red == 0)
    #expect(abs(color.alpha - 128.0 / 255.0) < 0.0001)
  }

  @Test("The leading hash is optional and the case does not matter")
  func toleratesHashAndCase() throws {
    let canonical = try OverlayColor(parsing: "#2B2E33")

    #expect(try OverlayColor(parsing: "2b2e33") == canonical)
    #expect(try OverlayColor(parsing: "  #2B2E33 ") == canonical)
  }

  @Test("A colour round-trips through its own spelling")
  func roundTripsThroughHex() throws {
    #expect(try OverlayColor(parsing: "#2B2E33").hexDescription == "#2B2E33FF")
    #expect(try OverlayColor(parsing: "#12345678").hexDescription == "#12345678")
  }

  @Test("Anything that is not six or eight hex digits is refused")
  func refusesMalformedColours() {
    for text in ["", "#", "#FFF", "#FFFFF", "#FFFFFFF", "#GGGGGG", "blue", "#FF FF FF"] {
      #expect(throws: OverlayColorError.malformed(text)) {
        try OverlayColor(parsing: text)
      }
    }
  }

  @Test("The default overlay colour is a matte graphite, fully opaque")
  func defaultIsOpaque() {
    #expect(AppConfig.default.overlayBackground.hexDescription == "#2B2E33C2")
  }
}
