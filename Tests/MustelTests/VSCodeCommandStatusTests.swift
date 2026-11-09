import Foundation
import XCTest
@testable import Mustel

final class VSCodeCommandStatusTests: XCTestCase {
    func testCompletionUsesElapsedTimeForBothCommands() {
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let reload = VSCodeCommandStatus(command: .hotReload, phase: .completed, completedAt: completedAt)
        let restart = VSCodeCommandStatus(command: .hotRestart, phase: .completed, completedAt: completedAt)

        XCTAssertEqual(reload.completionText(at: completedAt.addingTimeInterval(30)), "Hot reloaded 30s ago")
        XCTAssertEqual(
            restart.completionText(at: completedAt.addingTimeInterval(60)),
            "Hot restarted > 1m ago"
        )
        XCTAssertEqual(reload.completionText(at: completedAt.addingTimeInterval(-1)), "Hot reloaded 0s ago")
        XCTAssertEqual(
            reload.completionText(at: completedAt.addingTimeInterval(3_600)),
            "Hot reloaded more than one minute ago"
        )
    }

    func testRequestAndFailureRemainDistinct() {
        let requested = VSCodeCommandStatus(command: .hotRestart, phase: .requested)
        let failed = VSCodeCommandStatus(command: .hotReload, phase: .failed("not available"))

        XCTAssertTrue(requested.isInFlight)
        XCTAssertEqual(requested.text, "Requesting hot restart…")
        XCTAssertNil(requested.completedAt)
        XCTAssertTrue(failed.isFailure)
        XCTAssertEqual(failed.text, "Hot reload failed: not available")
    }
}
