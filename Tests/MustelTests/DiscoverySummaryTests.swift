import XCTest
@testable import Mustel

final class DiscoverySummaryTests: XCTestCase {
    func testNoRuns() {
        let summary = DiscoverySummary(
            discoveredTargetCount: 0,
            skippedRuns: 0,
            unsupportedRuns: 0,
            ideManagedRuns: 0
        )

        XCTAssertEqual(summary.statusText, "No attachable Flutter runs found.")
    }

    func testIDEManagedRunsTakePrecedence() {
        let summary = DiscoverySummary(
            discoveredTargetCount: 0,
            skippedRuns: 0,
            unsupportedRuns: 2,
            ideManagedRuns: 1
        )

        XCTAssertTrue(summary.statusText.hasPrefix("1 IDE-managed Flutter run(s) found."))
    }

    func testUnsupportedDesktopRuns() {
        let summary = DiscoverySummary(
            discoveredTargetCount: 0,
            skippedRuns: 0,
            unsupportedRuns: 2,
            ideManagedRuns: 0
        )

        XCTAssertEqual(
            summary.statusText,
            "Existing desktop/web runs need a VM Service info file (`--vmservice-out-file`) to attach automatically."
        )
    }

    func testSkippedRuns() {
        let summary = DiscoverySummary(
            discoveredTargetCount: 0,
            skippedRuns: 3,
            unsupportedRuns: 0,
            ideManagedRuns: 0
        )

        XCTAssertEqual(
            summary.statusText,
            "3 Flutter run session(s) could not be identified. 3 run(s) skipped; use `flutter run -d <device>` if the device is ambiguous."
        )
    }

    func testDetectedTargetsWithAdditionalHints() {
        let summary = DiscoverySummary(
            discoveredTargetCount: 2,
            skippedRuns: 1,
            unsupportedRuns: 1,
            ideManagedRuns: 1
        )

        XCTAssertEqual(
            summary.statusText,
            "2 existing Flutter target(s) detected. 1 run(s) skipped; use `flutter run -d <device>` if the device is ambiguous. Or launch desktop/web projects here. Skipped 1 IDE-managed run(s) to avoid conflicting with their IDE."
        )
    }
}
