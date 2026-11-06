import AppKit
import XCTest
@testable import Mustel

final class LottieAnimationTests: XCTestCase {
    func testLoadsBundledAnimations() throws {
        let idleToRun = try XCTUnwrap(LottieAnimation.named("idle-to-run"))
        XCTAssertEqual(idleToRun.frameRate, 30)
        XCTAssertEqual(idleToRun.frameCount, 8)

        let run = try XCTUnwrap(LottieAnimation.named("run"))
        XCTAssertEqual(run.frameCount, 11)

        let runToIdle = try XCTUnwrap(LottieAnimation.named("run-to-idle"))
        XCTAssertEqual(runToIdle.frameCount, 9)
    }

    func testRendersTemplateFramesAtRequestedSize() throws {
        let animation = try XCTUnwrap(LottieAnimation.named("run"))
        let size = CGSize(width: 28, height: 16)
        let frames = animation.renderFrames(cropRect: animation.contentBounds, size: size)

        XCTAssertEqual(frames.count, animation.frameCount)
        XCTAssertTrue(frames.allSatisfy(\.isTemplate))
        XCTAssertTrue(frames.allSatisfy { $0.size == size })
    }

    func testRenderedFrameContainsVisiblePixels() throws {
        let animation = try XCTUnwrap(LottieAnimation.named("run"))
        let image = try XCTUnwrap(animation.renderFrames(
            cropRect: animation.contentBounds,
            size: CGSize(width: 28, height: 16),
            scale: 3
        ).first)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var hasVisiblePixels = false
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    hasVisiblePixels = true
                    break
                }
            }
            if hasVisiblePixels {
                break
            }
        }

        XCTAssertTrue(hasVisiblePixels)
    }
}
