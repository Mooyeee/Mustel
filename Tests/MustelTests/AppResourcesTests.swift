import XCTest
@testable import Mustel

final class AppResourcesTests: XCTestCase {
    func testResolvesBundledResources() {
        XCTAssertNotNil(AppResources.url(forResource: "MustelMenuBar", withExtension: "png"))
        XCTAssertNotNil(AppResources.url(forResource: "FlutterDefaultIcon", withExtension: "png"))
        XCTAssertNotNil(AppResources.url(forResource: "FlutterLicense", withExtension: "txt"))
    }

    func testResourceCheckPasses() {
        XCTAssertEqual(ResourceCheck.run(), 0)
    }
}
