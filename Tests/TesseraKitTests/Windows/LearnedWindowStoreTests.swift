import Foundation
import Testing

@testable import TesseraKit

@Suite("LearnedWindowStore")
@MainActor
struct LearnedWindowStoreTests {
  @Test("A window survives being written and read back")
  func roundTripsThroughTheFile() {
    let signatures: Set<WindowSignature> = [
      WindowSignature(applicationName: "AmneziaVPN", title: "AmneziaVPN"),
      WindowSignature(applicationName: "Finder", title: "Downloads"),
    ]

    let parsed = LearnedWindowStore.parse(LearnedWindowStore.serialize(signatures))

    #expect(parsed == signatures)
  }

  @Test("The file is written in a stable order, so it does not churn")
  func serializesInAStableOrder() {
    let signatures: Set<WindowSignature> = [
      WindowSignature(applicationName: "Zed", title: "b"),
      WindowSignature(applicationName: "Arc", title: "b"),
      WindowSignature(applicationName: "Arc", title: "a"),
    ]

    let lines = LearnedWindowStore.serialize(signatures)
      .split(whereSeparator: \.isNewline)
      .filter { !$0.hasPrefix("#") }

    #expect(lines == ["Arc\ta", "Arc\tb", "Zed\tb"])
  }

  @Test("Comments and blank lines are ignored")
  func ignoresCommentsAndBlankLines() {
    let parsed = LearnedWindowStore.parse(
      """
      # a comment

      AmneziaVPN\tAmneziaVPN
      """
    )

    #expect(parsed == [WindowSignature(applicationName: "AmneziaVPN", title: "AmneziaVPN")])
  }

  @Test("A line nobody can parse is skipped, not fatal")
  func skipsUnparsableLines() {
    let parsed = LearnedWindowStore.parse(
      """
      no tab here
      \tmissing application
      Trailing\t
      Good\tWindow
      """
    )

    #expect(parsed == [WindowSignature(applicationName: "Good", title: "Window")])
  }

  @Test("A title with spaces and punctuation survives intact")
  func keepsTitlesVerbatim() {
    let signature = WindowSignature(
      applicationName: "Finder",
      title: "/Users/alex/Тезисы, черновик — 2026"
    )

    #expect(LearnedWindowStore.parse(LearnedWindowStore.serialize([signature])) == [signature])
  }

  @Test("Nothing learned yields a file with only its explanation")
  func serializesAnEmptySetAsCommentsOnly() {
    let lines = LearnedWindowStore.serialize([])
      .split(whereSeparator: \.isNewline)
      .filter { !$0.hasPrefix("#") }

    #expect(lines.isEmpty)
  }

  @Test("Learning is remembered across a restart")
  func learningPersists() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesseraTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("learned-windows.txt")
    let signature = WindowSignature(applicationName: "AmneziaVPN", title: "AmneziaVPN")

    let store = LearnedWindowStore(fileURL: fileURL)
    store.learn(signature)

    #expect(LearnedWindowStore(fileURL: fileURL).contains(signature))

    store.forget(signature)

    #expect(LearnedWindowStore(fileURL: fileURL).contains(signature) == false)
  }

  @Test("A missing file is not an error, it is an empty memory")
  func missingFileIsEmpty() {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesseraTests-\(UUID().uuidString)/learned-windows.txt")

    #expect(
      LearnedWindowStore(fileURL: missing)
        .contains(WindowSignature(applicationName: "Any", title: "Thing")) == false)
  }
}
