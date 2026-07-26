import XCTest
@testable import HealthExport

final class ServerURLBuilderTests: XCTestCase {
    func testParseHostWithEmbeddedPortAndPath() {
        let parsed = ServerURLBuilder.parseHostInput("https://api.example.com:8443/v1/data")
        XCTAssertEqual(parsed?.scheme, "https")
        XCTAssertEqual(parsed?.host, "api.example.com")
        XCTAssertEqual(parsed?.port, 8443)
        XCTAssertEqual(parsed?.embeddedPath, "/v1/data")
    }

    func testParseBareHostname() {
        let parsed = ServerURLBuilder.parseHostInput("workouts.example.com")
        XCTAssertEqual(parsed?.host, "workouts.example.com")
        XCTAssertNil(parsed?.port)
    }

    func testDefaultUploadPath() {
        let server = DestinationServer(
            name: "Test",
            host: "example.com",
            uploadPath: ""
        )
        switch ServerURLBuilder.uploadURL(for: server) {
        case .success(let url):
            XCTAssertEqual(url.path, "/workouts")
        case .failure:
            XCTFail("Expected valid URL")
        }
    }

    func testSeparatePortApplied() {
        let server = DestinationServer(
            name: "Test",
            host: "example.com",
            port: 9090,
            uploadPath: "/workouts"
        )
        switch ServerURLBuilder.uploadURL(for: server) {
        case .success(let url):
            XCTAssertEqual(url.host, "example.com")
            XCTAssertEqual(url.port, 9090)
            XCTAssertEqual(url.scheme, "https")
        case .failure:
            XCTFail("Expected valid URL")
        }
    }

    func testHTTPSchemeWhenInsecureEnabled() {
        let server = DestinationServer(
            name: "Test",
            host: "example.com",
            usesInsecureHTTP: true
        )
        switch ServerURLBuilder.uploadURL(for: server) {
        case .success(let url):
            XCTAssertEqual(url.scheme, "http")
        case .failure:
            XCTFail("Expected valid URL")
        }
    }

    func testDuplicateDestinationDetection() {
        let first = DestinationServer(name: "A", host: "example.com", uploadPath: "/workouts")
        let second = DestinationServer(name: "B", host: "https://example.com", uploadPath: "/workouts")

        switch ServerURLBuilder.validate(server: second, existingServers: [first]) {
        case .success:
            XCTFail("Expected duplicate validation failure")
        case .failure(let error):
            XCTAssertEqual(error, .duplicateDestination)
        }
    }

    func testDestinationKeyIsStable() {
        let server = DestinationServer(
            name: "Test",
            host: "https://Example.COM:443",
            uploadPath: "/workouts"
        )
        guard case .success(let normalized) = ServerURLBuilder.normalizedDestination(for: server) else {
            return XCTFail("Expected normalized destination")
        }
        XCTAssertEqual(
            ServerURLBuilder.destinationKey(for: normalized),
            "https://example.com:443/workouts"
        )
    }
}
