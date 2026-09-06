import AppKit
import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("AudioActivity")
struct AudioActivityTests {
  /// The mark is per application, not per window: a browser plays from one tab and
  /// every window it owns carries the mark, because that is as precise as macOS
  /// will say without an entitlement it does not hand out.
  @Test("Every window of a sounding application is marked")
  func marksTheWindowsOfASoundingApplication() {
    let tiles = [
      makeTile(id: 1, processID: 100),
      makeTile(id: 2, processID: 100),
      makeTile(id: 3, processID: 200),
    ]

    let marked = AudioActivity.marking(tiles, playing: [100])

    #expect(marked.map(\.isSounding) == [true, true, false])
  }

  @Test("Nothing playing leaves every tile as it was")
  func leavesTilesAloneWhenNothingPlays() {
    let tiles = [makeTile(id: 1, processID: 100), makeTile(id: 2, processID: 200)]

    #expect(AudioActivity.marking(tiles, playing: []).allSatisfy { !$0.isSounding })
  }

  /// A tile whose application has gone quiet since it was marked loses that mark —
  /// the list is rebuilt from what is playing now, not added to.
  @Test("A tile that has gone quiet loses the mark")
  func clearsTheMarkWhenTheSoundStops() {
    var tile = makeTile(id: 1, processID: 100)
    tile.isSounding = true

    #expect(AudioActivity.marking([tile], playing: [200]).first?.isSounding == false)
  }

  /// The process that plays is often a helper — a browser's audio comes from one —
  /// so the chain is walked up to the application. This one is walked from a real
  /// process: whatever is running the tests has an application above it or is one.
  @Test("A process resolves to an application")
  @MainActor
  func resolvesAProcessToItsApplication() {
    let owner = AudioActivity.applicationOwning(ProcessInfo.processInfo.processIdentifier)

    #expect(owner > 0)
    #expect(AudioActivity.parentProcess(of: ProcessInfo.processInfo.processIdentifier) > 0)
  }

  private func makeTile(id: CGWindowID, processID: pid_t) -> WindowTile {
    WindowTile(
      id: id,
      appName: "App",
      title: "Window",
      processID: processID,
      isActive: false,
      isMinimized: false,
      displayID: 1,
      spaceIndex: nil,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )
  }
}
