import Foundation

public protocol UserdataTransport: Sendable {
    func getSessionIdentity() async throws -> UserdataIdentity
    func getUserdata() async throws -> UserdataBlob
    func putUserdata(_ blob: UserdataBlob) async throws -> UserdataBlob
}

extension MuxCoreClient: UserdataTransport {}

public struct UserdataIdentity: Codable, Equatable, Sendable {
    public let userID: String
    public let tenantID: String?

    public init(userID: String, tenantID: String? = nil) {
        self.userID = userID
        self.tenantID = tenantID
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case tenantID = "tenant_id"
    }
}

/// One account record contains both the visible data and its unacknowledged revisions.
public protocol UserdataPersistence {
    func read(key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
}

public final class UserDefaultsUserdataPersistence: UserdataPersistence {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func read(key: String) throws -> Data? { defaults.data(forKey: key) }
    public func write(_ data: Data, key: String) throws { defaults.set(data, forKey: key) }
}

public enum UserdataSyncStatus: Equatable, Sendable {
    case signedOut, cached, pending, syncing, acknowledged
    case failed(String)
    case unavailable(String)

    public var message: String {
        switch self {
        case .signedOut: return "Sign in to sync your data."
        case .cached: return "Showing data saved on this Apple TV."
        case .pending: return "Changes saved on this Apple TV are waiting to sync."
        case .syncing: return "Syncing with your server…"
        case .acknowledged: return "Your server acknowledged the latest sync."
        case let .failed(message), let .unavailable(message): return message
        }
    }
}

/// Production sync logic shared by the app wrapper and package fixtures.
/// The BFF acknowledgement does not establish provider or cross-device durability.
@MainActor
public final class UserdataSyncStore {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case progress, favorites, prefs, playlists, queue
    }

    private struct Record: Codable {
        var blob = UserdataBlob(progress: [:], favorites: [:], prefs: .defaults, playlists: [], queue: [])
        var revision: UInt64 = 0
        var pending: [Field: UInt64] = [:]
        // The current BFF merges favorites by ID, so omissions may not remove them.
        var removedFavorites: Set<String> = []
        var progressChanges: Set<String> = []
        var favoriteChanges: Set<String> = []
        var preferenceChanges: Set<String> = []
    }

    public private(set) var status: UserdataSyncStatus = .signedOut
    public var blob: UserdataBlob { record.blob }
    public var hasPendingChanges: Bool { !record.pending.isEmpty }
    public var isSyncing: Bool { activeRequest != nil }
    public var canSync: Bool { session != nil && transport != nil && cacheReadable }
    public var onChange: (() -> Void)?
    public var onVerifiedIdentity: ((UserdataIdentity) -> Void)?

    private let persistence: any UserdataPersistence
    private var record = Record()
    private var key: String?
    private var session: MuxCoreSession?
    private var identity: UserdataIdentity?
    private var needsIdentity = true
    private var transport: (any UserdataTransport)?
    private var generation = UUID()
    private var activeRequest: UUID?
    private var cacheReadable = true
    // Preserve unsaved edits across sign-out/rebinding in this process if local storage fails.
    private var memoryRecords: [String: Record] = [:]

    public init(persistence: any UserdataPersistence = UserDefaultsUserdataPersistence()) {
        self.persistence = persistence
    }

    public func bind(session: MuxCoreSession?, transport: (any UserdataTransport)?) {
        generation = UUID()
        self.transport = transport
        record = Record()
        key = nil
        self.session = nil
        identity = nil
        needsIdentity = true
        cacheReadable = true
        guard let session else {
            status = .signedOut
            onChange?()
            return
        }
        guard !session.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .unavailable("This session has no stable account ID. Sign in again before saving changes.")
            onChange?()
            return
        }
        self.session = session
        if let saved = session.userdataIdentity, saved.userID == session.userID {
            load(identity: saved)
        } else {
            status = .unavailable("Connect to your server to verify this account before saving changes.")
        }
        onChange?()
    }

    private func load(identity: UserdataIdentity) {
        guard let session, let accountKey = Self.accountKey(session, identity: identity) else {
            cacheReadable = false
            status = .unavailable("This server address cannot be used to save account data.")
            return
        }
        self.identity = identity
        key = accountKey
        record = Record()
        cacheReadable = true
        do {
            if let memory = memoryRecords[accountKey] {
                record = memory
            } else if let data = try persistence.read(key: accountKey) {
                record = try JSONDecoder().decode(Record.self, from: data)
            }
            status = hasPendingChanges ? .pending : .cached
        } catch {
            // Never overwrite an unreadable record with an empty document.
            cacheReadable = false
            status = .unavailable("Saved data could not be read. It has been preserved; changes are disabled.")
        }
    }

    /// Mutations are recorded before a caller schedules any network work.
    public func update(_ field: Field, _ change: (inout UserdataBlob) -> Void) {
        guard key != nil, cacheReadable else { return }
        let previousFavorites = Set((record.blob.favorites ?? [:]).keys)
        let previous = record.blob
        change(&record.blob)
        record.revision += 1
        record.pending[field] = record.revision
        if field == .favorites {
            let currentFavorites = Set((record.blob.favorites ?? [:]).keys)
            record.removedFavorites.formUnion(previousFavorites.subtracting(currentFavorites))
            record.removedFavorites.subtract(currentFavorites)
            record.favoriteChanges.formUnion(currentFavorites.filter { previous.favorites?[$0] != record.blob.favorites?[$0] })
        }
        if field == .progress {
            record.progressChanges.formUnion((record.blob.progress ?? [:]).keys.filter {
                previous.progress?[$0] != record.blob.progress?[$0]
            })
        }
        if field == .prefs, let prefs = record.blob.prefs {
            do {
                record.preferenceChanges.formUnion(try prefs.changedPaths(from: previous.prefs ?? .defaults))
            } catch {
                status = .failed("Preferences could not be saved. Keep the app open and retry sync.")
                onChange?()
                return
            }
        }
        status = .pending
        _ = persist()
        onChange?()
    }

    /// A single flight includes reads and writes. Reads preserve pending local changes.
    /// Retries occur on an explicit refresh, foreground/sign-in, or a later mutation; no retry loop on failure.
    public func synchronize() async {
        guard canSync, activeRequest == nil, let transport else { return }
        if key != nil, !persist() { onChange?(); return }
        let binding = generation
        let requestID = UUID()
        activeRequest = requestID
        status = .syncing
        onChange?()
        defer {
            if activeRequest == requestID {
                activeRequest = nil
                onChange?()
                // Drain an old binding before sending another write, even on A → B → A.
                if generation != binding, canSync {
                    Task { await self.synchronize() }
                }
            }
        }
        do {
            if needsIdentity {
                let verified = try await transport.getSessionIdentity()
                guard generation == binding else { return }
                guard verified.userID == session?.userID, !verified.userID.isEmpty else {
                    status = .failed("The signed-in account changed. Sign in again before syncing.")
                    return
                }
                if identity?.userID != verified.userID || (identity?.tenantID ?? "") != (verified.tenantID ?? "") || key == nil {
                    load(identity: verified)
                }
                guard cacheReadable, key != nil else { return }
                identity = verified
                needsIdentity = false
                onVerifiedIdentity?(verified)
                status = .syncing
                onChange?()
            }
            repeat {
                let latest = try await transport.getUserdata()
                guard generation == binding else { return }
                guard checkIdentity(latest) else { return }
                if record.pending[.prefs] != nil {
                    // Preferences are a replacement object: rebase only edited leaves onto the latest document.
                    record.blob.prefs = try (latest.prefs ?? .defaults).applying(record.blob.prefs ?? .defaults, paths: record.preferenceChanges)
                }
                applyCleanFields(latest)
                guard persist() else { return }
                if !hasPendingChanges { break }
                let submitted = record.pending
                let sent = pendingBlob()
                let remote = try await transport.putUserdata(sent)
                guard generation == binding else { return }
                guard checkIdentity(remote) else { return }
                guard [Field.prefs, .playlists, .queue].allSatisfy({ confirms($0, sent: sent, remote: remote) }) else {
                    status = .failed("Your server did not return the submitted changes. They remain pending on this Apple TV.")
                    return
                }
                let beforeAcknowledgement = record
                var removalUnconfirmed = false
                var changeUnconfirmed = false
                for (field, revision) in submitted where record.pending[field] == revision {
                    if field == .favorites,
                       record.removedFavorites.contains(where: { remote.favorites?[$0] != nil }) {
                        removalUnconfirmed = true
                        continue
                    }
                    guard confirms(field, sent: sent, remote: remote) else {
                        changeUnconfirmed = true
                        continue
                    }
                    record.pending.removeValue(forKey: field)
                    if field == .favorites {
                        record.removedFavorites.removeAll()
                        record.favoriteChanges.removeAll()
                    }
                    if field == .progress { record.progressChanges.removeAll() }
                    if field == .prefs { record.preferenceChanges.removeAll() }
                }
                applyCleanFields(remote)
                guard persist() else {
                    // A failed acknowledgement save must not drop the durable retry intent.
                    record = beforeAcknowledgement
                    if let key { memoryRecords[key] = record }
                    return
                }
                if removalUnconfirmed {
                    status = .failed("Your server did not confirm favorite removal. The change remains pending on this Apple TV.")
                    return
                }
                if changeUnconfirmed {
                    status = .failed("Your server did not return the submitted changes. They remain pending on this Apple TV.")
                    return
                }
            } while hasPendingChanges
            status = .acknowledged
        } catch {
            guard generation == binding else { return }
            status = .failed(Self.failureMessage(error, pending: hasPendingChanges))
        }
    }

    private func pendingBlob() -> UserdataBlob {
        UserdataBlob(
            progress: record.pending[.progress] == nil ? nil : record.blob.progress?.filter { record.progressChanges.contains($0.key) },
            favorites: record.pending[.favorites] == nil ? nil : record.blob.favorites?.filter { record.favoriteChanges.contains($0.key) },
            // The provider fills omitted replacement sections with defaults. Preserve all three
            // from the fresh read, overlaid with any local pending changes, even on a progress PUT.
            prefs: record.blob.prefs,
            playlists: record.blob.playlists,
            queue: record.blob.queue
        )
    }

    private func checkIdentity(_ remote: UserdataBlob) -> Bool {
        guard remote.userID == identity?.userID, (remote.tenantID ?? "") == (identity?.tenantID ?? "") else {
            status = .failed("Your server returned a different or missing account ID. Saved changes remain on this Apple TV.")
            return false
        }
        return true
    }

    private func confirms(_ field: Field, sent: UserdataBlob, remote: UserdataBlob) -> Bool {
        switch field {
        case .progress:
            return (sent.progress ?? [:]).allSatisfy { remote.progress?[$0.key] == $0.value }
        case .favorites:
            return (sent.favorites ?? [:]).allSatisfy { remote.favorites?[$0.key] == $0.value }
        case .prefs: return remote.prefs == sent.prefs
        case .playlists: return (remote.playlists ?? []) == (sent.playlists ?? [])
        case .queue: return (remote.queue ?? []) == (sent.queue ?? [])
        }
    }

    private func applyCleanFields(_ remote: UserdataBlob) {
        // GET and PUT responses are full documents. Go omitempty may omit empty sections.
        if record.pending[.progress] == nil { record.blob.progress = remote.progress ?? [:] }
        if record.pending[.favorites] == nil { record.blob.favorites = remote.favorites ?? [:] }
        if record.pending[.prefs] == nil { record.blob.prefs = remote.prefs ?? .defaults }
        if record.pending[.playlists] == nil { record.blob.playlists = remote.playlists ?? [] }
        if record.pending[.queue] == nil { record.blob.queue = remote.queue ?? [] }
    }

    private func persist() -> Bool {
        guard let key, cacheReadable else { return false }
        memoryRecords[key] = record
        do {
            try persistence.write(JSONEncoder().encode(record), key: key)
            return true
        } catch {
            status = .failed("Changes could not be saved on this Apple TV. Keep the app open and retry sync.")
            return false
        }
    }

    private static func accountKey(_ session: MuxCoreSession, identity: UserdataIdentity) -> String? {
        guard !session.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let parts = URLComponents(url: session.baseURL, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        let port = parts.port ?? (scheme == "https" ? 443 : 80)
        // Length-independent encoding avoids collisions and deliberately excludes credentials/tokens.
        guard let data = try? JSONEncoder().encode([scheme, host, String(port), identity.tenantID ?? "", identity.userID]) else { return nil }
        return "muxcore.userdata.v2." + data.base64EncodedString()
    }

    private static func failureMessage(_ error: Error, pending: Bool) -> String {
        let retained = pending ? " Changes remain pending on this Apple TV." : " Showing data saved on this Apple TV."
        if case MuxCoreAPIError.unauthorized = error {
            return "Your session expired. Sign in again to retry sync." + retained
        }
        if case let MuxCoreAPIError.httpStatus(code, _) = error {
            return "Sync failed (HTTP \(code)). Retry when your server is available." + retained
        }
        return "Sync could not complete. Check your connection and retry." + retained
    }
}
