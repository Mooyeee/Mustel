import XCTest
@testable import Mustel

final class UpdateServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testParsesLatestReleaseAndSelectsMustelAsset() async throws {
        StubURLProtocol.handler = { request in
            let data = Data("""
            {
              "tag_name": "v0.2.0",
              "name": "Mustel 0.2.0",
              "body": "Release notes",
              "html_url": "https://github.com/Mooyeee/mustel/releases/tag/v0.2.0",
              "assets": [
                {
                  "name": "notes.txt",
                  "browser_download_url": "https://example.com/notes.txt",
                  "size": 12
                },
                {
                  "name": "Mustel.zip",
                  "browser_download_url": "https://example.com/Mustel.zip",
                  "size": 2048
                },
                {
                  "name": "mustel-vscode-0.1.2.vsix",
                  "browser_download_url": "https://example.com/mustel-vscode-0.1.2.vsix",
                  "size": 512
                },
                {
                  "name": "mustel-intellij-0.1.1.zip",
                  "browser_download_url": "https://example.com/mustel-intellij-0.1.1.zip",
                  "size": 1024
                }
              ]
            }
            """.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let release = try await service().latestRelease()

        XCTAssertEqual(release?.version, AppVersion("0.2.0"))
        XCTAssertEqual(release?.assetName, "Mustel.zip")
        XCTAssertEqual(release?.assetURL?.absoluteString, "https://example.com/Mustel.zip")
        XCTAssertEqual(release?.assetSize, 2048)
        XCTAssertEqual(release?.visualStudioCodeAsset?.version, AppVersion("0.1.2"))
        XCTAssertEqual(release?.intellijAsset?.version, AppVersion("0.1.1"))
        XCTAssertEqual(release?.notes, "Release notes")
    }

    func testReturnsNilWhenNoReleaseExists() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let release = try await service().latestRelease()

        XCTAssertNil(release)
    }

    func testThrowsForUnexpectedStatus() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await service().latestRelease()
            XCTFail("Expected an HTTP error")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .httpStatus(500))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func service() -> GitHubUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return GitHubUpdateService(
            repository: "Mooyeee/mustel",
            session: URLSession(configuration: configuration)
        )
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: TestError.failed("Missing handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
