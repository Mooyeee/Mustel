import XCTest
@testable import Mustel

final class AppVersionTests: XCTestCase {
    func testParsesCommonTagFormats() {
        XCTAssertEqual(AppVersion("v0.2.0")?.description, "0.2.0")
        XCTAssertEqual(AppVersion("1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("release-1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("Mustel 0.3.1")?.description, "0.3.1")
        XCTAssertNil(AppVersion("latest"))
    }

    func testComparesVersionsWithDifferentComponentCounts() {
        XCTAssertLessThan(AppVersion("0.1.6")!, AppVersion("0.1.10")!)
        XCTAssertLessThan(AppVersion("0.1")!, AppVersion("0.1.1")!)
        XCTAssertEqual(AppVersion("0.2")!, AppVersion("0.2.0")!)
        XCTAssertGreaterThan(AppVersion("1.0.0")!, AppVersion("0.9.9")!)
    }

    func testComparesNumericComponentsRatherThanStrings() {
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
        XCTAssertGreaterThan(AppVersion("10.0.0")!, AppVersion("9.9.9")!)
    }
}
