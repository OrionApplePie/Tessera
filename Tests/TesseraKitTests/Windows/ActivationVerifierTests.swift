import CoreGraphics
import Foundation
import Testing

@testable import TesseraKit

@Suite("ActivationVerifier")
struct ActivationVerifierTests {
  private let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
  private let signature = WindowSignature(applicationName: "AmneziaVPN", title: "AmneziaVPN")

  @Test("Nothing is judged before the Space switch has had time to finish")
  func waitsOutTheGracePeriod() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)

    let outcomes = verifier.evaluate(
      onScreen: [],
      existing: [1],
      now: activatedAt.addingTimeInterval(1.4)
    )

    #expect(outcomes.isEmpty)
  }

  @Test("A window still absent after the grace period did not come forward")
  func reportsAWindowThatNeverArrived() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)

    let outcomes = verifier.evaluate(
      onScreen: [],
      existing: [1],
      now: activatedAt.addingTimeInterval(1.5)
    )

    #expect(outcomes == [ActivationVerifier.Outcome(signature: signature, cameForward: false)])
  }

  @Test("A window that arrived is reported as having come forward")
  func reportsAWindowThatArrived() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)

    let outcomes = verifier.evaluate(
      onScreen: [1],
      existing: [1],
      now: activatedAt.addingTimeInterval(2)
    )

    #expect(outcomes == [ActivationVerifier.Outcome(signature: signature, cameForward: true)])
  }

  @Test("A window that closed in the meantime is not condemned for it")
  func passesNoVerdictOnAClosedWindow() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)

    let outcomes = verifier.evaluate(
      onScreen: [],
      existing: [],
      now: activatedAt.addingTimeInterval(2)
    )

    #expect(outcomes.isEmpty)
  }

  @Test("A verdict is passed once and then forgotten")
  func judgesEachActivationOnce() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)

    _ = verifier.evaluate(onScreen: [], existing: [1], now: activatedAt.addingTimeInterval(2))
    let second = verifier.evaluate(
      onScreen: [], existing: [1], now: activatedAt.addingTimeInterval(3))

    #expect(second.isEmpty)
  }

  @Test("Activating the same window again restarts its clock")
  func reactivationRestartsTheClock() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt.addingTimeInterval(1))

    #expect(
      verifier.evaluate(
        onScreen: [], existing: [1], now: activatedAt.addingTimeInterval(2)
      ).isEmpty)
  }

  @Test("Several activations are judged independently")
  func judgesSeveralActivations() {
    let other = WindowSignature(applicationName: "Finder", title: "Downloads")
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)
    verifier.recordActivation(of: 2, signature: other, at: activatedAt)

    let outcomes = verifier.evaluate(
      onScreen: [2],
      existing: [1, 2],
      now: activatedAt.addingTimeInterval(2)
    )

    #expect(
      outcomes == [
        ActivationVerifier.Outcome(signature: signature, cameForward: false),
        ActivationVerifier.Outcome(signature: other, cameForward: true),
      ])
  }

  /// Stepping asks for a window on every press. Without this the one before is
  /// judged for being off screen a second later, which it is because the next one
  /// was asked for — and a window that came exactly as told gets hidden for it.
  @Test("A window superseded by another request is not judged at all")
  func doesNotJudgeASupersededActivation() {
    var verifier = ActivationVerifier()
    verifier.recordActivation(of: 1, signature: signature, at: activatedAt)
    verifier.forgetPending()

    let outcomes = verifier.evaluate(
      onScreen: [], existing: [1], now: activatedAt.addingTimeInterval(verifier.grace + 1))

    #expect(outcomes.isEmpty)
  }

}
