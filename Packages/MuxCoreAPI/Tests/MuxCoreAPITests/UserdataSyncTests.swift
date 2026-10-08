import Foundation
import XCTest
@testable import MuxCoreAPI

private final class MemoryPersistence: UserdataPersistence {
    var values: [String: Data] = [:]
    var failWrites = false
    func read(key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if failWrites { throw URLError(.cannotWriteToFile) }
        values[key] = data
    }
}

private actor ControlledTransport: UserdataTransport {
    enum Call { case identity, get, put(UserdataBlob) }
    var identity = UserdataIdentity(userID: "alice")
    var identityError: Error?
    private var heldReads = 0
    private var snapshot = UserdataBlob(progress: [:], favorites: [:], prefs: .defaults, playlists: [], queue: [], userID: "alice")
    private(set) var calls: [Call] = []
    private var responses: [CheckedContinuation<UserdataBlob, Error>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func setIdentity(_ value: UserdataIdentity) { identity = value }
    func failIdentity(_ error: Error) { identityError = error }
    func holdNextRead() { heldReads += 1 }
    func setSnapshot(_ blob: UserdataBlob) { snapshot = blob }
    func getSessionIdentity() async throws -> UserdataIdentity {
        calls.append(.identity)
        if let identityError { throw identityError }
        return identity
    }
    func getUserdata() async throws -> UserdataBlob {
        if heldReads > 0 {
            heldReads -= 1
            return try await request(.get)
        }
        calls.append(.get)
        var current = snapshot
        current.userID = identity.userID
        current.tenantID = identity.tenantID
        return current
    }
    func putUserdata(_ blob: UserdataBlob) async throws -> UserdataBlob { try await request(.put(blob)) }
    private func request(_ call: Call) async throws -> UserdataBlob {
        calls.append(call)
        return try await withCheckedThrowingContinuation { continuation in
            responses.append(continuation)
            for (count, waiter) in waiters where calls.count >= count { waiter.resume() }
            waiters.removeAll { calls.count >= $0.0 }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func respond(_ blob: UserdataBlob) {
        snapshot = blob
        responses.removeFirst().resume(returning: blob)
    }
    func fail(_ error: Error) { responses.removeFirst().resume(throwing: error) }
    func put(at index: Int) -> UserdataBlob? {
        if case let .put(blob) = calls[index] { return blob }
        return nil
    }
}

@MainActor
final class UserdataSyncTests: XCTestCase {
    private func session(_ user: String = "alice", server: String = "https://fixture.invalid", tenant: String? = nil, verified: Bool = true, token: String = "fixture-token") -> MuxCoreSession {
        MuxCoreSession(baseURL: URL(string: server)!, sessionToken: token, username: user, userID: user,
                       userdataIdentity: verified ? UserdataIdentity(userID: user, tenantID: tenant) : nil)
    }
    private func blob(user: String? = "alice", tenant: String? = nil, queue: [QueueItem]? = nil, favorites: [String: FavoriteEntry]? = nil) -> UserdataBlob {
        UserdataBlob(progress: nil, favorites: favorites, prefs: .defaults, playlists: nil, queue: queue, userID: user, tenantID: tenant)
    }
    private func item(_ id: String) -> QueueItem {
        QueueItem(id: id, kind: .movie, title: id, href: "/movies/\(id)", streamURL: nil, posterURL: nil)
    }
    private func favorite(_ id: String) -> FavoriteEntry {
        FavoriteEntry(id: id, kind: .movie, title: id, posterURL: nil, href: "/movies/\(id)", year: nil)
    }
    private func make(_ cache: MemoryPersistence = MemoryPersistence()) -> (UserdataSyncStore, ControlledTransport) {
        let store = UserdataSyncStore(persistence: cache)
        let transport = ControlledTransport()
        store.bind(session: session(), transport: transport)
        return (store, transport)
    }
    private func assertFailure(_ store: UserdataSyncStore, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failed = store.status else { return XCTFail("Expected failure: \(store.status)", file: file, line: line) }
        XCTAssertTrue(store.status.message.contains(text), file: file, line: line)
    }

    func testFailedWriteSurvivesReconstructionAndRetryKeepsPending() async {
        let cache = MemoryPersistence()
        let (store, transport) = make(cache)
        store.update(.queue) { $0.queue = [item("one")] }
        let first = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        await transport.fail(URLError(.notConnectedToInternet))
        await first.value
        XCTAssertTrue(store.hasPendingChanges)
        assertFailure(store, contains: "pending")

        let (restarted, retry) = make(cache)
        XCTAssertEqual(restarted.blob.queue?.map(\.id), ["one"])
        XCTAssertTrue(restarted.hasPendingChanges)
        let second = Task { await restarted.synchronize() }
        await retry.waitForCalls(3)
        let sent = await retry.put(at: 2)
        XCTAssertEqual(sent?.queue?.map(\.id), ["one"])
        XCTAssertNotNil(sent?.prefs)
        XCTAssertNil(sent?.favorites)
        XCTAssertNil(sent?.userID, "Clients do not select a principal in userdata payloads")
        await retry.respond(blob(queue: [item("one")]))
        await second.value
        XCTAssertFalse(restarted.hasPendingChanges)
        XCTAssertEqual(restarted.status, .acknowledged)
    }

    func testPullCannotOverwriteEditMadeWhileReadSuspended() async {
        let (store, transport) = make()
        await transport.holdNextRead()
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        store.update(.queue) { $0.queue = [item("local")] }
        await store.synchronize() // Coalesced with the read, never a parallel write.
        await transport.respond(blob(queue: [item("remote")]))
        await transport.waitForCalls(3)
        let sent = await transport.put(at: 2)
        XCTAssertEqual(sent?.queue?.map(\.id), ["local"])
        XCTAssertEqual(store.blob.queue?.map(\.id), ["local"])
        await transport.respond(blob(queue: [item("local")]))
        await task.value
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testOldWriteAcknowledgesOnlySubmittedRevision() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("first")] }
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        store.update(.queue) { $0.queue = [item("second")] }
        await transport.respond(blob(queue: [item("first")]))
        await transport.waitForCalls(5)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["second"])
        XCTAssertTrue(store.hasPendingChanges)
        let latest = await transport.put(at: 4)
        XCTAssertEqual(latest?.queue?.map(\.id), ["second"])
        await transport.respond(blob(queue: [item("second")]))
        await task.value
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testLogoutAndAccountReturnDrainOldWriteBeforeNewOne() async {
        let cache = MemoryPersistence()
        let (store, old) = make(cache)
        store.update(.queue) { $0.queue = [item("first")] }
        let task = Task { await store.synchronize() }
        await old.waitForCalls(3)
        store.bind(session: nil, transport: nil)
        XCTAssertTrue(store.blob.queue?.isEmpty == true)
        XCTAssertFalse(store.hasPendingChanges)
        let other = ControlledTransport()
        store.bind(session: session("bob"), transport: other)
        XCTAssertTrue(store.blob.queue?.isEmpty == true)
        let current = ControlledTransport()
        store.bind(session: session(), transport: current)
        store.update(.queue) { $0.queue = [item("second")] }
        await store.synchronize()
        let currentCalls = await current.calls.count
        XCTAssertEqual(currentCalls, 0, "Do not send a newer write ahead of an old binding")
        await old.respond(blob(queue: [item("first")]))
        await task.value
        await current.waitForCalls(3)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["second"])
        let sent = await current.put(at: 2)
        XCTAssertEqual(sent?.queue?.map(\.id), ["second"])
        let completed = expectation(description: "Latest binding finishes its drained sync")
        store.onChange = {
            if !store.isSyncing, store.status == .acknowledged { completed.fulfill() }
        }
        await current.respond(blob(queue: [item("second")]))
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testLatePullAfterLogoutCannotRestoreVisibleData() async {
        let (store, transport) = make()
        await transport.holdNextRead()
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        store.bind(session: nil, transport: nil)
        await transport.respond(blob(queue: [item("old-account")]))
        await task.value
        XCTAssertEqual(store.status, .signedOut)
        XCTAssertTrue(store.blob.queue?.isEmpty == true)
    }

    func testServerTenantAndUserCachesAreIsolatedAndTokenRotationReusesScope() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("alice")] }
        for isolated in [session("bob"), session(server: "https://other.invalid"), session(tenant: "other-household")] {
            store.bind(session: isolated, transport: transport)
            XCTAssertTrue(store.blob.queue?.isEmpty == true)
            XCTAssertFalse(store.hasPendingChanges)
        }
        store.bind(session: session(server: "https://FIXTURE.invalid:443/", token: "new-fixture-token"), transport: transport)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["alice"])
        XCTAssertTrue(store.hasPendingChanges)
    }

    func testLegacyOwnerlessDataIsNeverAssignedToLogin() async throws {
        let suite = "UserdataSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = try JSONEncoder().encode([item("legacy")])
        defaults.set(legacy, forKey: "muxcore.queue")
        let store = UserdataSyncStore(persistence: UserDefaultsUserdataPersistence(defaults: defaults))
        store.bind(session: session(), transport: ControlledTransport())
        XCTAssertTrue(store.blob.queue?.isEmpty == true)
        XCTAssertEqual(defaults.data(forKey: "muxcore.queue"), legacy)
        store.bind(session: session(""), transport: ControlledTransport())
        store.update(.queue) { $0.queue = [item("ignored")] }
        XCTAssertFalse(store.canSync)
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testNewSessionNeedsVerifiedIdentityBeforeCacheOrMutation() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("cached")] }
        store.bind(session: session(verified: false), transport: transport)
        XCTAssertTrue(store.blob.queue?.isEmpty == true)
        store.update(.queue) { $0.queue = [item("unverified")] }
        XCTAssertFalse(store.hasPendingChanges)
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        let sent = await transport.put(at: 2)
        XCTAssertEqual(sent?.queue?.map(\.id), ["cached"])
        await transport.respond(blob(queue: [item("cached")]))
        await task.value
    }

    func testFailedIdentityCheckNeverUploadsPendingData() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("cached")] }
        await transport.failIdentity(MuxCoreAPIError.unauthorized)
        await store.synchronize()
        XCTAssertTrue(store.hasPendingChanges)
        assertFailure(store, contains: "Sign in again")
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testVerifiedDifferentUserCannotReadOrWriteUserdata() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("cached")] }
        await transport.setIdentity(UserdataIdentity(userID: "bob"))
        await store.synchronize()
        XCTAssertTrue(store.hasPendingChanges)
        assertFailure(store, contains: "account changed")
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testVerifiedTenantChangeNeverUploadsPreviousTenantData() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("old-tenant")] }
        await transport.setIdentity(UserdataIdentity(userID: "alice", tenantID: "new-tenant"))
        await transport.holdNextRead()
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        let put = await transport.put(at: 1)
        XCTAssertNil(put)
        XCTAssertTrue(store.blob.queue?.isEmpty == true)
        await transport.respond(blob(tenant: "new-tenant"))
        await task.value
        store.bind(session: session(), transport: transport)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["old-tenant"])
        XCTAssertTrue(store.hasPendingChanges)
    }

    func testWrongOrMissingResponseIdentityRetainsPending() async {
        for response in [blob(user: nil, queue: [item("local")]), blob(user: "bob", queue: [item("local")]), blob(tenant: "wrong-tenant", queue: [item("local")])] {
            let (store, transport) = make()
            store.update(.queue) { $0.queue = [item("local")] }
            let task = Task { await store.synchronize() }
            await transport.waitForCalls(3)
            await transport.respond(response)
            await task.value
            XCTAssertTrue(store.hasPendingChanges)
            XCTAssertEqual(store.blob.queue?.map(\.id), ["local"])
            assertFailure(store, contains: "account ID")
        }
    }

    func testIncompleteSuccessfulResponseDoesNotDiscardSubmittedSections() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("local")] }
        store.update(.favorites) { $0.favorites = ["favorite": favorite("favorite")] }
        store.update(.prefs) { $0.prefs?.playback.autoplayNext = true }
        await transport.holdNextRead()
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        await transport.respond(blob()) // Rebase preferences before sending the replacement object.
        await transport.waitForCalls(3)
        await transport.respond(blob())
        await task.value
        XCTAssertTrue(store.hasPendingChanges)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["local"])
        XCTAssertNotNil(store.blob.favorites?["favorite"])
        XCTAssertTrue(store.blob.prefs?.playback.autoplayNext == true)
        assertFailure(store, contains: "did not return")
    }

    func testUnionMergeCannotAcknowledgeFavoriteRemovalButOtherSectionsClear() async {
        let (store, transport) = make()
        await transport.holdNextRead()
        let load = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        await transport.respond(blob(favorites: ["one": favorite("one")]))
        await load.value
        store.update(.favorites) { $0.favorites?.removeValue(forKey: "one") }
        store.update(.queue) { $0.queue = [item("queued")] }
        let push = Task { await store.synchronize() }
        await transport.waitForCalls(4)
        await transport.respond(blob(queue: [item("queued")], favorites: ["one": favorite("one")]))
        await push.value
        XCTAssertNil(store.blob.favorites?["one"])
        XCTAssertTrue(store.hasPendingChanges)
        assertFailure(store, contains: "favorite removal")
        let retry = Task { await store.synchronize() }
        await transport.waitForCalls(6)
        let sent = await transport.put(at: 5)
        XCTAssertEqual(sent?.queue?.map(\.id), ["queued"], "Preserve the fresh remote queue during removal retry")
        XCTAssertEqual(sent?.favorites?.count, 0)
        await transport.fail(URLError(.timedOut))
        await retry.value
    }

    func testReaddingFavoriteDuringDeleteDoesNotRetainOldRemovalError() async {
        let (store, transport) = make()
        store.update(.favorites) { $0.favorites = ["one": favorite("one")] }
        store.update(.favorites) { $0.favorites = [:] }
        let push = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        store.update(.favorites) { $0.favorites = ["one": favorite("one")] }
        await transport.respond(blob(favorites: ["one": favorite("one")]))
        await transport.waitForCalls(5)
        await transport.respond(blob(favorites: ["one": favorite("one")]))
        await push.value
        XCTAssertEqual(store.status, .acknowledged)
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testEmptyReplacementAcknowledgementAllowsOmittedGoSections() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [] }
        store.update(.playlists) { $0.playlists = [] }
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        let sent = await transport.put(at: 2)
        XCTAssertEqual(sent?.queue?.count, 0)
        XCTAssertEqual(sent?.playlists?.count, 0)
        await transport.respond(blob())
        await task.value
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testLocalWriteFailureBlocksNetworkAndSurvivesRebindInMemory() async {
        let cache = MemoryPersistence()
        let (store, transport) = make(cache)
        cache.failWrites = true
        store.update(.queue) { $0.queue = [item("unsaved")] }
        await store.synchronize()
        assertFailure(store, contains: "Keep the app open")
        let count = await transport.calls.count
        XCTAssertEqual(count, 0)
        store.bind(session: nil, transport: nil)
        store.bind(session: session(), transport: transport)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["unsaved"])
        cache.failWrites = false
        let retry = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        await transport.respond(blob(queue: [item("unsaved")]))
        await retry.value
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testUnreadableCacheIsPreservedAndBlocksMutation() async {
        let cache = MemoryPersistence()
        let (store, transport) = make(cache)
        store.update(.queue) { $0.queue = [item("saved")] }
        let key = cache.values.keys.first!
        cache.values[key] = Data("broken".utf8)
        let restarted = UserdataSyncStore(persistence: cache)
        restarted.bind(session: session(), transport: transport)
        restarted.update(.queue) { $0.queue = [item("replacement")] }
        await restarted.synchronize()
        XCTAssertFalse(restarted.canSync)
        XCTAssertEqual(cache.values[key], Data("broken".utf8))
    }

    func testPreferencesRebasePreservesUnknownFieldsAndNewerLocalEdit() async throws {
        let cache = MemoryPersistence()
        let (store, transport) = make(cache)
        store.update(.prefs) { $0.prefs?.playback.autoplayNext = true }
        await transport.holdNextRead()
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        store.update(.prefs) { $0.prefs?.home.showFavorites = false }
        let remotePrefs = try JSONDecoder().decode(UserPreferences.self, from: Data(#"{"controls":{"seek":45,"future":[null,true,"x"]},"home":{"showNextUp":false,"customShelf":"remote"},"display":{"theme":"light","futureSize":1234567890123456789},"playback":{"customMode":"retain"}}"#.utf8))
        var remote = blob()
        remote.prefs = remotePrefs
        await transport.respond(remote)
        await transport.waitForCalls(3)
        let submitted = await transport.put(at: 2)
        let sent = try XCTUnwrap(submitted)
        XCTAssertTrue(sent.prefs?.playback.autoplayNext == true)
        XCTAssertFalse(sent.prefs?.home.showFavorites ?? true)
        XCTAssertFalse(sent.prefs?.home.showNextUp ?? true)
        XCTAssertEqual(sent.prefs?.display.theme, "light")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sent.prefs)) as? [String: Any])
        XCTAssertEqual((json["controls"] as? [String: Any])?["seek"] as? Int, 45)
        XCTAssertEqual((json["home"] as? [String: Any])?["customShelf"] as? String, "remote")
        XCTAssertEqual((json["playback"] as? [String: Any])?["customMode"] as? String, "retain")
        var response = sent
        response.userID = "alice"
        await transport.respond(response)
        await task.value
        XCTAssertFalse(store.hasPendingChanges)
        let (restored, _) = make(cache)
        XCTAssertEqual(restored.blob.prefs, sent.prefs, "Unknown fields survive the cache codec too")
    }

    func testProgressWritePreservesProviderReplacementSections() async throws {
        let (store, transport) = make()
        var existing = blob(queue: [item("remote-queue")])
        existing.prefs = .defaults
        existing.prefs?.display.theme = "light"
        existing.playlists = [Playlist(id: "remote-list", name: "Keep", itemIds: ["one"])]
        await transport.setSnapshot(existing)
        let progress = ProgressEntry(id: "movie", kind: .movie, title: "Movie", posterURL: nil, href: "/movies/movie", streamURL: nil, positionSec: 25, durationSec: 100, updatedAt: "2026-10-08T22:00:00Z", watched: false)
        store.update(.progress) { $0.progress = ["movie": progress] }
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        let candidate = await transport.put(at: 2)
        let sent = try XCTUnwrap(candidate)
        // Model internal/store.ParseBlob: absent replacement sections become defaults/empty.
        var providerResult = sent
        providerResult.prefs = sent.prefs ?? .defaults
        providerResult.playlists = sent.playlists ?? []
        providerResult.queue = sent.queue ?? []
        providerResult.userID = "alice"
        XCTAssertEqual(providerResult.prefs?.display.theme, "light")
        XCTAssertEqual(providerResult.queue?.map(\.id), ["remote-queue"])
        XCTAssertEqual(providerResult.playlists?.map(\.id), ["remote-list"])
        XCTAssertNil(sent.favorites)
        await transport.respond(providerResult)
        await task.value
        XCTAssertEqual(store.blob.progress?["movie"], progress)
        XCTAssertFalse(store.hasPendingChanges)
    }

    func testUserDefaultsReloadRestoresPendingWithoutCachingBearer() async throws {
        let suite = "UserdataSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = UserDefaultsUserdataPersistence(defaults: defaults)
        let store = UserdataSyncStore(persistence: cache)
        store.bind(session: session(), transport: ControlledTransport())
        store.update(.queue) { $0.queue = [item("durable")] }
        let reloaded = UserdataSyncStore(persistence: UserDefaultsUserdataPersistence(defaults: UserDefaults(suiteName: suite)!))
        reloaded.bind(session: session(token: "rotated-token"), transport: ControlledTransport())
        XCTAssertEqual(reloaded.blob.queue?.map(\.id), ["durable"])
        XCTAssertTrue(reloaded.hasPendingChanges)
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("muxcore.userdata.v2.") {
            XCTAssertFalse(key.contains("fixture-token"))
            let data = try XCTUnwrap(value as? Data)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("fixture-token"))
        }
    }

    func testFailedAcknowledgementSaveRetainsRetryIntent() async {
        let cache = MemoryPersistence()
        let (store, transport) = make(cache)
        store.update(.queue) { $0.queue = [item("pending")] }
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        cache.failWrites = true
        await transport.respond(blob(queue: [item("pending")]))
        await task.value
        XCTAssertTrue(store.hasPendingChanges)
        assertFailure(store, contains: "Keep the app open")
        cache.failWrites = false
        let (restarted, _) = make(cache)
        XCTAssertTrue(restarted.hasPendingChanges)
        XCTAssertEqual(restarted.blob.queue?.map(\.id), ["pending"])
    }

    func testFailedRebaseReadRetainsPendingAndNeverWrites() async {
        let (store, transport) = make()
        store.update(.queue) { $0.queue = [item("pending")] }
        await transport.holdNextRead()
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(2)
        await transport.fail(MuxCoreAPIError.httpStatus(503, "fixture unavailable"))
        await task.value
        XCTAssertTrue(store.hasPendingChanges)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["pending"])
        assertFailure(store, contains: "503")
        let calls = await transport.calls.count
        XCTAssertEqual(calls, 2)
    }

    func testAcknowledgementCannotDropUnchangedReplacementSections() async throws {
        let (store, transport) = make()
        var remote = blob(queue: [item("remote-queue")])
        remote.playlists = [Playlist(id: "list", name: "Keep", itemIds: ["movie"])]
        await transport.setSnapshot(remote)
        store.update(.favorites) { $0.favorites = ["favorite": favorite("favorite")] }
        let task = Task { await store.synchronize() }
        await transport.waitForCalls(3)
        let submitted = await transport.put(at: 2)
        var incomplete = try XCTUnwrap(submitted)
        incomplete.userID = "alice"
        incomplete.queue = nil
        incomplete.playlists = nil
        await transport.respond(incomplete)
        await task.value
        XCTAssertTrue(store.hasPendingChanges)
        XCTAssertEqual(store.blob.queue?.map(\.id), ["remote-queue"])
        XCTAssertEqual(store.blob.playlists?.map(\.id), ["list"])
        assertFailure(store, contains: "did not return")
    }
}
