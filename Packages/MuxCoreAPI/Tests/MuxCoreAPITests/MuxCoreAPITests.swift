import XCTest
@testable import MuxCoreAPI

final class MuxCoreAPITests: XCTestCase {
    func testNormalizeBaseURLAddsHTTPS() {
        let url = MuxCoreClient.normalizeBaseURL("mux.zem.systems")
        XCTAssertEqual(url?.absoluteString, "https://mux.zem.systems")
    }

    func testNormalizeBaseURLTrimsTrailingSlash() {
        let url = MuxCoreClient.normalizeBaseURL("https://mux.zem.systems/")
        XCTAssertEqual(url?.absoluteString, "https://mux.zem.systems")
    }
}
