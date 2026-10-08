import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import MuxCoreAPI

private final class FixtureURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (Int, Data))?

    static func install(_ callback: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock()
        handler = callback
        lock.unlock()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let callback = Self.handler
        Self.lock.unlock()
        do {
            let (status, data) = try XCTUnwrap(callback)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class UserdataRequestTests: XCTestCase {
    private func client() -> MuxCoreClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = MuxCoreSession(baseURL: URL(string: "https://fixture.invalid")!, sessionToken: "fixture-bff-token", username: "alice", userID: "alice")
        return MuxCoreClient(session: session, configuration: configuration)
    }

    func testSessionAndUserdataRequestsUseBFFBearerWithoutCookiesOrPrincipalOverrides() async throws {
        FixtureURLProtocol.install { request in
            XCTAssertEqual(request.url?.host, "fixture.invalid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-bff-token")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies, "Ambient browser cookies must not override the BFF bearer")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Muxcore-User-Id"))
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            switch request.url?.path {
            case "/api/session":
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, Data(#"{"user_id":"alice","tenant_id":"household","username":"Alice"}"#.utf8))
            case "/api/userdata":
                if request.httpMethod == "PUT" {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                    let data = try XCTUnwrap(request.httpBody)
                    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual((body["queue"] as? [Any])?.count, 0)
                    XCTAssertNil(body["user_id"])
                    XCTAssertNil(body["tenant_id"])
                } else { XCTAssertEqual(request.httpMethod, "GET") }
                return (200, Data(#"{"user_id":"alice","tenant_id":"household","queue":[]}"#.utf8))
            default: throw URLError(.unsupportedURL)
            }
        }
        let api = client()
        let identity = try await api.getSessionIdentity()
        XCTAssertEqual(identity, UserdataIdentity(userID: "alice", tenantID: "household"))
        let read = try await api.getUserdata()
        XCTAssertEqual(read.userID, "alice")
        XCTAssertEqual(read.tenantID, "household")
        let written = try await api.putUserdata(UserdataBlob(progress: nil, favorites: nil, prefs: nil, playlists: nil, queue: []))
        XCTAssertEqual(written.queue?.count, 0)
    }

    func testHTTPFailuresAndMalformedSuccessAreNotAcknowledgements() async {
        for code in [401, 403, 500, 503, 200] {
            FixtureURLProtocol.install { _ in (code, Data(code == 200 ? "not-json".utf8 : "fixture failure".utf8)) }
            do {
                _ = try await client().putUserdata(UserdataBlob(progress: nil, favorites: nil, prefs: nil, playlists: nil, queue: []))
                XCTFail("HTTP \(code) fixture unexpectedly acknowledged")
            } catch MuxCoreAPIError.unauthorized { XCTAssertEqual(code, 401) }
            catch let MuxCoreAPIError.httpStatus(status, _) { XCTAssertEqual(status, code) }
            catch MuxCoreAPIError.decoding { XCTAssertEqual(code, 200) }
            catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testPreferencesUnknownFieldsRoundtripThroughHTTP() async throws {
        FixtureURLProtocol.install { request in
            if request.httpMethod == "PUT" {
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let prefs = try XCTUnwrap(json["prefs"] as? [String: Any])
                XCTAssertEqual((prefs["controls"] as? [String: Any])?["step"] as? Int, 42)
                XCTAssertEqual((prefs["home"] as? [String: Any])?["custom"] as? String, "retain")
                XCTAssertEqual((prefs["playback"] as? [String: Any])?["autoplayNext"] as? Bool, true)
                return (200, body)
            }
            return (200, Data(#"{"user_id":"alice","prefs":{"controls":{"step":42},"home":{"custom":"retain"}}}"#.utf8))
        }
        let api = client()
        var blob = try await api.getUserdata()
        blob.prefs?.playback.autoplayNext = true
        blob.userID = nil
        let written = try await api.putUserdata(blob)
        XCTAssertEqual(written.prefs, blob.prefs)
    }
}
