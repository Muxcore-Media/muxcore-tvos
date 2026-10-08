import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import XCTest
@testable import MuxCoreAPI

/// Real loopback HTTP verifies URLSession's default cookie/redirect behavior beyond URLProtocol interception.
private final class LoopbackHTTPFixture: @unchecked Sendable {
    private final class Requests: @unchecked Sendable {
        let lock = NSLock()
        var values: [String] = []
        func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
        func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
    }
    private let listener: Int32
    private let received = Requests()
    private let finished = DispatchGroup()
    let baseURL: URL
    var requests: [String] { received.snapshot() }

    init(status: String = "200 OK", headers: String = "", body: String = #"{"user_id":"alice","queue":[]}"#) throws {
        #if canImport(Darwin)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #else
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            Self.closeSocket(descriptor)
            throw POSIXError(.EIO)
        }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
        }
        listener = descriptor
        baseURL = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))")!
        let received = self.received
        let finished = self.finished
        finished.enter()
        let response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\(headers)\r\n\(body)".utf8)
        DispatchQueue.global().async {
            defer { finished.leave() }
            while true {
                let connection = accept(descriptor, nil, nil)
                guard connection >= 0 else { return }
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                _ = setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while data.count < 128_000 {
                    let count = recv(connection, &buffer, buffer.count, 0)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                    let text = String(decoding: data, as: UTF8.self)
                    if let split = text.range(of: "\r\n\r\n") {
                        let length = text[..<split.lowerBound].components(separatedBy: "\r\n")
                            .first { $0.lowercased().hasPrefix("content-length:") }
                            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                        if text[split.upperBound...].utf8.count >= length { break }
                    }
                }
                received.append(String(decoding: data, as: UTF8.self))
                response.withUnsafeBytes { bytes in
                    #if canImport(Darwin)
                    _ = send(connection, bytes.baseAddress, bytes.count, 0)
                    #else
                    _ = send(connection, bytes.baseAddress, bytes.count, Int32(MSG_NOSIGNAL))
                    #endif
                }
                Self.closeSocket(connection)
            }
        }
    }

    deinit {
        _ = shutdown(listener, Int32(SHUT_RDWR))
        Self.closeSocket(listener)
        finished.wait()
    }
    private static func closeSocket(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #else
        _ = Glibc.close(descriptor)
        #endif
    }
}

final class UserdataHTTPPolicyTests: XCTestCase {
    private func client(_ baseURL: URL) -> MuxCoreClient {
        MuxCoreClient(session: MuxCoreSession(baseURL: baseURL, sessionToken: "fixture-bearer", username: "alice", userID: "alice"))
    }
    private func seedCookie() throws -> HTTPCookie {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "session", .value: "other-account-fixture"]))
        HTTPCookieStorage.shared.setCookie(cookie)
        return cookie
    }

    func testDefaultTransportNeverSendsAmbientCookie() async throws {
        let fixture = try LoopbackHTTPFixture(headers: "Set-Cookie: session=server-fixture; Path=/\r\n")
        let cookie = try seedCookie()
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let api = client(fixture.baseURL)
        _ = try await api.getSessionIdentity()
        _ = try await api.putUserdata(UserdataBlob(progress: nil, favorites: nil, prefs: nil, playlists: nil, queue: []))
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertTrue(request.lowercased().contains("authorization: bearer fixture-bearer"))
            XCTAssertFalse(request.lowercased().contains("\r\ncookie:"), request)
        }
        XCTAssertTrue(requests[0].hasPrefix("GET /api/session "))
        XCTAssertTrue(requests[1].hasPrefix("PUT /api/userdata "))
    }

    func testDefaultTransportRejectsCrossOriginRedirectForReadAndWrite() async throws {
        let target = try LoopbackHTTPFixture()
        let fixture = try LoopbackHTTPFixture(status: "307 Temporary Redirect", headers: "Location: \(target.baseURL)/api/userdata\r\n")
        let api = client(fixture.baseURL)
        for write in [false, true] {
            do {
                if write {
                    _ = try await api.putUserdata(UserdataBlob(progress: nil, favorites: nil, prefs: nil, playlists: nil, queue: []))
                } else { _ = try await api.getSessionIdentity() }
                XCTFail("Redirect unexpectedly followed")
            } catch let MuxCoreAPIError.httpStatus(status, _) { XCTAssertEqual(status, 307) }
        }
        XCTAssertEqual(fixture.requests.count, 2)
        XCTAssertEqual(target.requests.count, 0, "A redirect must never receive the bearer or write")
    }
}
