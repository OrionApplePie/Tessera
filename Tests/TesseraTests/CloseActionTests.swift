import Testing

@testable import Tessera

@Suite("CloseAction")
struct CloseActionTests {
  @Test("Quitting the application can be said three ways")
  func parsesQuit() throws {
    #expect(try CloseAction(parsing: "quit") == .quitApplication)
    #expect(try CloseAction(parsing: "application") == .quitApplication)
    #expect(try CloseAction(parsing: "app") == .quitApplication)
  }

  @Test("Closing only the window can be said two ways")
  func parsesWindow() throws {
    #expect(try CloseAction(parsing: "window") == .closeWindow)
    #expect(try CloseAction(parsing: "close") == .closeWindow)
  }

  @Test("Case and padding do not matter")
  func toleratesCaseAndWhitespace() throws {
    #expect(try CloseAction(parsing: "  QUIT ") == .quitApplication)
  }

  @Test("Anything else is refused")
  func refusesAnythingElse() {
    for text in ["", "kill", "hide", "terminate"] {
      #expect(throws: CloseActionError.unknown(text)) { try CloseAction(parsing: text) }
    }
  }

  @Test("An action spells itself the same way whichever spelling built it")
  func nameIsCanonical() throws {
    #expect(try CloseAction(parsing: "app").name == "quit")
    #expect(try CloseAction(parsing: "close").name == "window")
  }

  @Test("The shortcut quits the application by default")
  func defaultQuitsTheApplication() {
    #expect(AppConfig.default.closeAction == .quitApplication)
  }
}
