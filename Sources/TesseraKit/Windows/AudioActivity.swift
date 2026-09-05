import AppKit
import CoreAudio
import Darwin

/// Which applications are making a sound right now.
///
/// CoreAudio keeps an object for every process that has touched the audio system,
/// and each of them will say whether it is playing at this moment. That is the
/// whole of it — no private framework, no entitlement, and nothing about *what* is
/// playing: since macOS 15.4 the now-playing information is behind an entitlement
/// third parties do not get, so a tile can say that a window's application is
/// sounding and nothing more.
///
/// The process that plays is often not the application. Measured: a YouTube tab in
/// Arc plays from `Browser Helper`, a child of `Arc.app`, and Chrome, Safari and
/// Electron applications are all built the same way. So each sounding process is
/// walked up its parents until it reaches something the switcher lists.
@MainActor
struct AudioActivity {
  private let logger: AppLogger

  init(debugMode: Bool) {
    self.logger = AppLogger(debugMode: debugMode, category: .preview)
  }

  /// The same tiles, with the ones whose application is sounding marked.
  func marking(_ tiles: [WindowTileModel]) -> [WindowTileModel] {
    Self.marking(tiles, playing: playingApplications())
  }

  /// Kept apart from the asking so it can be tested: what CoreAudio answers is the
  /// machine's business, what is done with the answer is ours.
  nonisolated static func marking(
    _ tiles: [WindowTileModel],
    playing: Set<pid_t>
  ) -> [WindowTileModel] {
    guard !playing.isEmpty else {
      return tiles
    }

    return tiles.map { tile in
      var tile = tile
      tile.isSounding = playing.contains(tile.processID)

      return tile
    }
  }

  /// The applications that are playing, by process id.
  ///
  /// Empty on macOS 13, where CoreAudio has no list of processes to ask — the map
  /// simply says nothing about sound there, which is better than guessing.
  func playingApplications() -> Set<pid_t> {
    guard #available(macOS 14.2, *) else {
      return []
    }

    let playing = Self.processesRunningOutput()

    guard !playing.isEmpty else {
      return []
    }

    var applications: Set<pid_t> = []

    for process in playing {
      applications.insert(Self.applicationOwning(process))
    }

    logger.debug("Sounding applications: \(applications.sorted())")

    return applications
  }

  /// The processes CoreAudio says are putting sound out at this moment.
  @available(macOS 14.2, *)
  private static func processesRunningOutput() -> [pid_t] {
    var address = AudioObjectPropertyAddress(
      selector: kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0

    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
      size > 0
    else {
      return []
    }

    var objects = [AudioObjectID](
      repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)

    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
    else {
      return []
    }

    return objects.compactMap { object in
      guard number(of: object, kAudioProcessPropertyIsRunningOutput) == 1 else {
        return nil
      }

      let pid = number(of: object, kAudioProcessPropertyPID)

      return pid > 0 ? pid_t(pid) : nil
    }
  }

  /// One numeric property of an audio object, or zero when it will not say.
  @available(macOS 14.2, *)
  private static func number(
    of object: AudioObjectID,
    _ selector: AudioObjectPropertySelector
  ) -> Int32 {
    var address = AudioObjectPropertyAddress(selector: selector)
    var value: Int32 = 0
    var size = UInt32(MemoryLayout<Int32>.size)

    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
      return 0
    }

    return value
  }

  /// The application a process belongs to: itself, if it is one, and otherwise the
  /// nearest parent that is.
  ///
  /// Walked rather than assumed, and bounded: a cycle in the parent chain would
  /// otherwise be a hang, and eight steps is more than any real tree of helpers.
  static func applicationOwning(_ process: pid_t) -> pid_t {
    var current = process

    for _ in 0..<8 {
      if NSRunningApplication(processIdentifier: current)?.activationPolicy != nil {
        return current
      }

      let parent = parentProcess(of: current)

      guard parent > 1, parent != current else {
        return current
      }

      current = parent
    }

    return current
  }

  /// The parent of a process, asked of the kernel.
  nonisolated static func parentProcess(of process: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, process]

    guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else {
      return 0
    }

    return info.kp_eproc.e_ppid
  }
}

extension AudioObjectPropertyAddress {
  /// Every property here is read from the object as a whole, so the scope and the
  /// element are always the same two constants.
  init(selector: AudioObjectPropertySelector) {
    self.init(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }
}
