import Testing

@testable import TesseraKit

/// What the report says, which is the only part of a private-framework lookup that
/// can be tested without the framework: whether it opened and what answered is a
/// fact about the machine, but what that means for the switcher is ours.
@Suite("SpaceQuery.Availability")
struct SpaceQueryAvailabilityTests {
  @Test("A configuration that never asked is not incomplete")
  func offByConfigurationIsComplete() {
    let report = SpaceQuery.Availability(isEnabled: false, isOpen: false, found: [:])

    #expect(report.isComplete)
    #expect(report.summary.contains("off by configuration"))
  }

  @Test("A framework that did not open is reported as such")
  func aClosedFrameworkIsIncomplete() {
    let report = SpaceQuery.Availability(isEnabled: true, isOpen: false, found: [:])

    #expect(!report.isComplete)
    #expect(report.summary.contains("did not open"))
  }

  /// The failure this is for: the framework is there, one call has been renamed,
  /// and nothing says so unless someone looks.
  @Test("A missing call is named")
  func aMissingCallIsNamed() {
    let report = SpaceQuery.Availability(
      isEnabled: true,
      isOpen: true,
      found: ["SLSMainConnectionID": true, "SLSGetActiveSpace": false]
    )

    #expect(!report.isComplete)
    #expect(report.missing == ["SLSGetActiveSpace"])
    #expect(report.summary.contains("SLSGetActiveSpace"))
  }

  @Test("Everything found is everything available")
  func allFoundIsComplete() {
    let report = SpaceQuery.Availability(
      isEnabled: true, isOpen: true, found: ["SLSMainConnectionID": true])

    #expect(report.isComplete)
    #expect(report.summary.contains("all 1 calls available"))
  }
}
