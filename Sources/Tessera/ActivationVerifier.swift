import CoreGraphics
import Foundation

/// Watches what happens after a window is asked to come forward.
///
/// The verdict is deliberately not read straight away: switching Spaces takes an
/// animation, and a window judged before it lands would be condemned for being
/// slow. A window still absent after the grace period, while still existing, did
/// not come.
struct ActivationVerifier {
  struct Outcome: Equatable {
    let signature: WindowSignature
    let cameForward: Bool
  }

  /// Long enough for a Space switch and its animation to finish.
  static let grace: TimeInterval = 1.5

  private var pending: [CGWindowID: (signature: WindowSignature, activatedAt: Date)] = [:]

  mutating func recordActivation(
    of windowID: CGWindowID,
    signature: WindowSignature,
    at date: Date = Date()
  ) {
    pending[windowID] = (signature, date)
  }

  /// Judges the activations old enough to judge, and forgets them either way.
  ///
  /// A window that has closed in the meantime gets no verdict: it did not refuse
  /// to come forward, it stopped existing.
  mutating func evaluate(
    onScreen: Set<CGWindowID>,
    existing: Set<CGWindowID>,
    now: Date = Date()
  ) -> [Outcome] {
    var outcomes: [Outcome] = []

    for (windowID, entry) in pending where now.timeIntervalSince(entry.activatedAt) >= Self.grace {
      pending[windowID] = nil

      guard existing.contains(windowID) else {
        continue
      }

      outcomes.append(
        Outcome(signature: entry.signature, cameForward: onScreen.contains(windowID)))
    }

    return outcomes.sorted { $0.signature < $1.signature }
  }
}
