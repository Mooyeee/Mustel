import XCTest
@testable import Mustel

final class MachineProtocolDecoderTests: XCTestCase {
    private let decoder = MachineProtocolDecoder()

    func testDecodesSingleEvent() {
        let line = #"{"event":"app.start","params":{"appId":"app-1"}}"#

        XCTAssertEqual(
            decoder.decode(line),
            [.event(name: "app.start", appID: "app-1", error: nil, trace: nil)]
        )
    }

    func testDecodesArrayOfMessages() {
        let line = #"[{"event":"app.start","params":{"appId":"app-1"}},{"id":7,"result":true}]"#

        XCTAssertEqual(
            decoder.decode(line),
            [
                .event(name: "app.start", appID: "app-1", error: nil, trace: nil),
                .response(id: "7", error: nil)
            ]
        )
    }

    func testDecodesStringError() {
        let line = #"{"event":"app.stop","params":{"error":"boom","trace":"trace line"}}"#

        XCTAssertEqual(
            decoder.decode(line),
            [.event(name: "app.stop", appID: nil, error: "boom", trace: "trace line")]
        )
    }

    func testDecodesObjectError() {
        let line = #"{"event":"app.stop","params":{"error":{"message":"boom"}}}"#
        let output = decoder.decode(line)

        XCTAssertEqual(output.count, 1)
        guard case let .event(name, _, error, _) = output[0] else {
            return XCTFail("Expected an event")
        }
        XCTAssertEqual(name, "app.stop")
        XCTAssertEqual(error, #"{"message":"boom"}"#)
    }

    func testDecodesErrorResponse() {
        let line = #"{"id":"request-1","error":"rejected"}"#

        XCTAssertEqual(
            decoder.decode(line),
            [.response(id: "request-1", error: "rejected")]
        )
    }

    func testIgnoresInvalidJSON() {
        XCTAssertEqual(decoder.decode("not json"), [])
        XCTAssertEqual(decoder.decode(#"{"unrelated":true}"#), [])
    }
}
