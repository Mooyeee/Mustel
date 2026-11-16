import AppKit
import SwiftUI
import XCTest
@testable import Mustel

@MainActor
final class ScanningButtonTests: XCTestCase {
    func testScanningButtonExpandsAndCollapses() {
        func button(isScanning: Bool) -> some View {
            Button {} label: {
                ScanningButtonLabel(isScanning: isScanning)
            }
            .roundIconButtonStyle()
        }

        let host = NSHostingView(rootView: button(isScanning: false))
        let collapsed = host.fittingSize
        host.rootView = button(isScanning: true)
        let expanded = host.fittingSize
        host.rootView = button(isScanning: false)
        let collapsedAgain = host.fittingSize

        XCTAssertEqual(collapsed.width, 32, accuracy: 1)
        XCTAssertGreaterThan(expanded.width, collapsed.width + 100)
        XCTAssertEqual(expanded.height, collapsed.height, accuracy: 1)
        XCTAssertEqual(collapsedAgain.width, collapsed.width, accuracy: 1)
    }
}
