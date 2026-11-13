import XCTest
@testable import Mustel

@MainActor
final class LogoAnimatorTests: XCTestCase {
    func testDisabledAnimationsNeverStartWhileScanning() {
        let animator = LogoAnimator()

        animator.setAnimationsEnabled(false)
        animator.setScanning(true)

        XCTAssertFalse(animator.isAnimating)
    }

    func testDisablingAnimationsStopsRunningFrames() {
        let animator = LogoAnimator()

        animator.setScanning(true)
        XCTAssertTrue(animator.isAnimating)

        animator.setAnimationsEnabled(false)

        XCTAssertFalse(animator.isAnimating)
    }

    func testEnablingAnimationsResumesWhileScanning() {
        let animator = LogoAnimator()
        animator.setAnimationsEnabled(false)
        animator.setScanning(true)

        animator.setAnimationsEnabled(true)

        XCTAssertTrue(animator.isAnimating)
        animator.stop()
    }
}
