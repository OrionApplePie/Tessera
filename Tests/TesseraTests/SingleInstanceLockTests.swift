import Foundation
import Testing

@testable import Tessera

/// `flock` is held per open file description, so two locks on one path contend
/// even inside a single process. That is what makes these tests possible without
/// spawning a second `tessera run`.
@Suite("SingleInstanceLock")
struct SingleInstanceLockTests {
  @Test("The first instance acquires the lock")
  func acquiresAnUncontendedLock() throws {
    try withLockURL { lockURL in
      let lock = SingleInstanceLock(lockURL: lockURL)
      defer { lock.release() }

      let acquired = try lock.tryAcquire()
      #expect(acquired == true)
    }
  }

  @Test("Acquiring creates the lock directory that does not exist yet")
  func createsTheLockDirectory() throws {
    try withLockURL(subdirectory: "tessera") { lockURL in
      let lock = SingleInstanceLock(lockURL: lockURL)
      defer { lock.release() }

      let acquired = try lock.tryAcquire()
      #expect(acquired == true)
      #expect(FileManager.default.fileExists(atPath: lockURL.path))
    }
  }

  @Test("The holder writes its own pid, so a human can see who owns the lock")
  func writesTheOwningProcessID() throws {
    try withLockURL { lockURL in
      let lock = SingleInstanceLock(lockURL: lockURL)
      defer { lock.release() }

      let acquired = try lock.tryAcquire()
      #expect(acquired == true)

      let contents = try String(contentsOf: lockURL, encoding: .utf8)
      #expect(contents == "\(ProcessInfo.processInfo.processIdentifier)\n")
    }
  }

  @Test("A second instance is refused while the first still holds the lock")
  func refusesASecondInstance() throws {
    try withLockURL { lockURL in
      let holder = SingleInstanceLock(lockURL: lockURL)
      defer { holder.release() }
      let held = try holder.tryAcquire()
      #expect(held == true)

      let duplicate = SingleInstanceLock(lockURL: lockURL)
      defer { duplicate.release() }

      let acquiredTwice = try duplicate.tryAcquire()
      #expect(acquiredTwice == false)
    }
  }

  @Test("Releasing lets the next instance in, which is what makes restart work")
  func releasingLetsTheNextInstanceIn() throws {
    try withLockURL { lockURL in
      let first = SingleInstanceLock(lockURL: lockURL)
      let firstAcquired = try first.tryAcquire()
      #expect(firstAcquired == true)
      first.release()

      let second = SingleInstanceLock(lockURL: lockURL)
      defer { second.release() }

      let secondAcquired = try second.tryAcquire()
      #expect(secondAcquired == true)
    }
  }

  @Test("Acquiring twice from one instance is a no-op rather than a second lock")
  func acquiringTwiceIsIdempotent() throws {
    try withLockURL { lockURL in
      let lock = SingleInstanceLock(lockURL: lockURL)
      defer { lock.release() }

      let firstAcquired = try lock.tryAcquire()
      let secondAcquired = try lock.tryAcquire()
      #expect(firstAcquired == true)
      #expect(secondAcquired == true)

      // A second acquire that had really opened a second descriptor would leak it,
      // and this single release would not hand the lock on.
      lock.release()

      let other = SingleInstanceLock(lockURL: lockURL)
      defer { other.release() }
      let otherAcquired = try other.tryAcquire()
      #expect(otherAcquired == true)
    }
  }

  @Test("Releasing a lock that was never acquired is harmless")
  func releasingAnUnacquiredLockIsHarmless() throws {
    try withLockURL { lockURL in
      SingleInstanceLock(lockURL: lockURL).release()

      let lock = SingleInstanceLock(lockURL: lockURL)
      defer { lock.release() }
      let acquired = try lock.tryAcquire()
      #expect(acquired == true)
    }
  }

  // MARK: - Helpers

  private func withLockURL(
    subdirectory: String? = nil,
    _ body: (URL) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesseraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var lockURL = directory
    if let subdirectory {
      lockURL = lockURL.appendingPathComponent(subdirectory, isDirectory: true)
    }

    try body(lockURL.appendingPathComponent("tessera.lock"))
  }
}
