import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("WindowOrder")
struct WindowOrderTests {
  @Test("Each order has a name, and a spelling or two")
  func parsesEveryOrder() throws {
    #expect(try WindowOrder(parsing: "title") == .title)
    #expect(try WindowOrder(parsing: "titles") == .title)
    #expect(try WindowOrder(parsing: "application") == .application)
    #expect(try WindowOrder(parsing: "apps") == .application)
    #expect(try WindowOrder(parsing: "stable") == .stable)
    #expect(try WindowOrder(parsing: "fixed") == .stable)
  }

  @Test("Case and padding do not matter")
  func toleratesCaseAndWhitespace() throws {
    #expect(try WindowOrder(parsing: "  STABLE ") == .stable)
  }

  @Test("Anything else is refused")
  func refusesAnythingElse() {
    for text in ["", "recent", "mru", "alphabetical"] {
      #expect(throws: WindowOrderError.unknown(text)) { try WindowOrder(parsing: text) }
    }
  }

  @Test("Sorting by title is the default")
  func defaultOrdersByTitle() {
    #expect(AppConfig.default.windowOrder == .title)
  }
}

@Suite("WindowOrderRegistry")
struct WindowOrderRegistryTests {
  @Test("First places are handed out alphabetically, so the list starts sensible")
  func seedsAlphabetically() {
    var registry = WindowOrderRegistry()

    let places = registry.sequence(for: [
      makeWindow(id: 3, appName: "Safari"),
      makeWindow(id: 1, appName: "Arc"),
      makeWindow(id: 2, appName: "Finder"),
    ])

    #expect(places[1] == 0)
    #expect(places[2] == 1)
    #expect(places[3] == 2)
  }

  @Test("A place, once given, is kept whatever the window does")
  func keepsPlacesAcrossRefreshes() {
    var registry = WindowOrderRegistry()
    let first = registry.sequence(for: [
      makeWindow(id: 1, appName: "Arc"), makeWindow(id: 2, appName: "Safari"),
    ])

    // The title changed and the windows arrive in the other order.
    let second = registry.sequence(for: [
      makeWindow(id: 2, appName: "Safari", title: "Something else"),
      makeWindow(id: 1, appName: "Arc", title: "Another page"),
    ])

    #expect(second == first)
  }

  @Test("A new window goes to the end rather than into the middle")
  func appendsNewcomers() {
    var registry = WindowOrderRegistry()
    _ = registry.sequence(for: [makeWindow(id: 2, appName: "Safari")])

    // Alphabetically Arc would come first, but the list has already been laid out.
    let places = registry.sequence(for: [
      makeWindow(id: 2, appName: "Safari"), makeWindow(id: 1, appName: "Arc"),
    ])

    #expect(places[2] == 0)
    #expect(places[1] == 1)
  }

  @Test("A closed window frees its place")
  func forgetsClosedWindows() {
    var registry = WindowOrderRegistry()
    _ = registry.sequence(for: [makeWindow(id: 1), makeWindow(id: 2)])

    let places = registry.sequence(for: [makeWindow(id: 2)])

    #expect(places.count == 1)
    #expect(places[2] == 1)
  }

  @Test("A window that comes back is a new window, and goes to the end")
  func reopenedWindowsGoToTheEnd() {
    var registry = WindowOrderRegistry()
    _ = registry.sequence(for: [makeWindow(id: 1), makeWindow(id: 2)])
    _ = registry.sequence(for: [makeWindow(id: 2)])

    let places = registry.sequence(for: [makeWindow(id: 2), makeWindow(id: 1)])

    #expect(places[2] == 1)
    #expect(places[1] == 2)
  }

  @Test("An arrangement made by hand replaces every place")
  func arrangeReplacesEveryPlace() {
    var registry = WindowOrderRegistry()
    _ = registry.sequence(for: [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)])

    registry.arrange([3, 1, 2])

    let places = registry.sequence(for: [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)])
    #expect(places[3] == 0)
    #expect(places[1] == 1)
    #expect(places[2] == 2)
  }

  @Test("A window left out of an arrangement is placed after it")
  func arrangeAppendsWhatItLeftOut() {
    var registry = WindowOrderRegistry()
    registry.arrange([2, 1])

    let places = registry.sequence(for: [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 9)])

    #expect(places[2] == 0)
    #expect(places[1] == 1)
    #expect(places[9] == 2)
  }

  private func makeWindow(
    id: CGWindowID,
    appName: String = "Finder",
    title: String = "Downloads"
  ) -> DiscoveredWindow {
    DiscoveredWindow(
      id: id,
      appName: appName,
      title: title,
      processID: 100,
      frame: CGRect(x: 0, y: 0, width: 800, height: 600),
      isOnScreen: true,
      isMinimized: false,
      displayID: 1
    )
  }
}
