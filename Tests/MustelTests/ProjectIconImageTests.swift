import CoreGraphics
import XCTest
@testable import Mustel

final class ProjectIconImageTests: XCTestCase {
    func testRemovesAsymmetricTransparentMargins() throws {
        let image = try makeImage(width: 20, height: 16, rect: CGRect(x: 3, y: 2, width: 10, height: 7))
        let cropped = try XCTUnwrap(ProjectIconImage.removingTransparentMargins(from: image))

        XCTAssertEqual(cropped.width, 10)
        XCTAssertEqual(cropped.height, 7)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: cropped.width,
            height: cropped.height,
            bitsPerComponent: 8,
            bytesPerRow: cropped.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        let pixels = Data(bytes: try XCTUnwrap(context.data), count: cropped.width * cropped.height * 4)
        XCTAssertTrue(pixels.enumerated().filter { $0.offset % 4 == 3 }.allSatisfy { $0.element == 255 })
    }

    func testKeepsOpaqueImagesAndRejectsEmptyImages() throws {
        let opaque = try makeImage(width: 10, height: 8, rect: CGRect(x: 0, y: 0, width: 10, height: 8))
        let result = try XCTUnwrap(ProjectIconImage.removingTransparentMargins(from: opaque))
        XCTAssertEqual(result.width, 10)
        XCTAssertEqual(result.height, 8)

        let transparent = try makeImage(width: 10, height: 8, rect: .zero)
        XCTAssertNil(ProjectIconImage.removingTransparentMargins(from: transparent))
    }

    private func makeImage(width: Int, height: Int, rect: CGRect) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        return try XCTUnwrap(context.makeImage())
    }
}
