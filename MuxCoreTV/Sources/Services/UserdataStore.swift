import Foundation
import MuxCoreAPI

@MainActor
final class UserdataStore: ObservableObject {
    @Published private(set) var progress: [String: ProgressEntry] = [:]
    @Published private(set) var favorites: [String: FavoriteEntry] = [:]
    @Published private(set) var prefs: UserPreferences = .defaults
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var syncStatus: UserdataSyncStatus = .signedOut
    @Published private(set) var hasPendingChanges = false
    @Published private(set) var isSyncing = false
    @Published private(set) var canSync = false

    private let sync = UserdataSyncStore()
    var onVerifiedIdentity: ((UserdataIdentity) -> Void)?

    init() {
        sync.onChange = { [weak self] in self?.refreshSnapshot() }
        sync.onVerifiedIdentity = { [weak self] identity in self?.onVerifiedIdentity?(identity) }
    }

    func bind(client: MuxCoreClient?) {
        sync.bind(session: client?.session, transport: client)
    }

    func pullFromServer() async { await sync.synchronize() }
    func pushToServer() async { await sync.synchronize() }

    private func refreshSnapshot() {
        progress = sync.blob.progress ?? [:]
        favorites = sync.blob.favorites ?? [:]
        prefs = sync.blob.prefs ?? .defaults
        playlists = sync.blob.playlists ?? []
        queue = sync.blob.queue ?? []
        syncStatus = sync.status
        hasPendingChanges = sync.hasPendingChanges
        isSyncing = sync.isSyncing
        canSync = sync.canSync
    }

    private func change(_ field: UserdataSyncStore.Field, _ update: (inout UserdataBlob) -> Void) {
        sync.update(field, update)
        Task { await sync.synchronize() }
    }

    func continueWatching(limit: Int = 24) -> [ProgressEntry] {
        progress.values
            .filter { entry in
                guard entry.watched != true else { return false }
                guard entry.positionSec > 5 else { return false }
                if entry.durationSec > 0, entry.positionSec / entry.durationSec >= 0.92 { return false }
                return true
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    func listFavorites() -> [FavoriteEntry] {
        favorites.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func isFavorite(id: String) -> Bool { favorites[id] != nil }

    @discardableResult
    func toggleFavorite(_ entry: FavoriteEntry) -> Bool {
        change(.favorites) { blob in
            var next = blob.favorites ?? [:]
            if next[entry.id] != nil { next.removeValue(forKey: entry.id) }
            else { next[entry.id] = entry }
            blob.favorites = next
        }
        return favorites[entry.id] != nil
    }

    func getProgress(id: String) -> ProgressEntry? { progress[id] }

    func upsertProgress(_ entry: ProgressEntry) {
        var next = entry
        next.updatedAt = ISO8601DateFormatter().string(from: Date())
        if next.watched != true, next.durationSec > 0, next.positionSec / next.durationSec >= 0.92 {
            next.watched = true
            next.positionSec = 0
        }
        if next.watched == true { next.positionSec = 0 }
        change(.progress) { blob in
            var entries = blob.progress ?? [:]
            entries[next.id] = next
            blob.progress = entries
        }
    }

    func updatePreferences(_ patch: (inout UserPreferences) -> Void) {
        var next = prefs
        patch(&next)
        change(.prefs) { $0.prefs = next }
    }

    func saveQueue(_ items: [QueueItem]) {
        change(.queue) { $0.queue = items }
    }

    func enqueue(_ item: QueueItem) {
        var next = queue.filter { $0.id != item.id }
        next.append(item)
        saveQueue(next)
    }

    func dequeue(id: String) {
        saveQueue(queue.filter { $0.id != id })
    }

    func clearQueue() { saveQueue([]) }

    func savePlaylists(_ items: [Playlist]) {
        change(.playlists) { $0.playlists = items }
    }

    func resolveNextUp(fetchShow: (String) async throws -> TVShow, limit: Int = 12) async -> [NextUpEntry] {
        let continueIDs = Set(continueWatching(limit: 100).map(\.id))
        var out: [NextUpEntry] = []
        var seen = Set<String>()
        var cache: [String: TVShow] = [:]

        for p in progress.values.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if out.count >= limit { break }
            guard p.kind == .episode || p.kind == .tv else { continue }
            let watched = p.watched == true || (p.durationSec > 0 && p.positionSec / p.durationSec >= 0.92)
            guard watched else { continue }
            guard let showID = showID(from: p.href) else { continue }
            let show: TVShow
            if let cached = cache[showID] {
                show = cached
            } else if let fetched = try? await fetchShow(showID) {
                cache[showID] = fetched
                show = fetched
            } else { continue }

            let next: Episode?
            if p.kind == .episode {
                next = nextEpisode(after: p.id, in: show)
            } else {
                next = flattenEpisodes(show).first { ep in
                    ep.hasFile && !(progress[ep.id]?.watched == true)
                }
            }
            guard let ep = next, !seen.contains(ep.id), !continueIDs.contains(ep.id) else { continue }
            seen.insert(ep.id)
            let label = "S\(String(format: "%02d", ep.seasonNumber))E\(String(format: "%02d", ep.episodeNumber))"
            out.append(NextUpEntry(
                id: ep.id,
                title: "\(show.title) \(label)\(ep.title.isEmpty ? "" : " · \(ep.title)")",
                posterURL: show.posterURL,
                streamURL: ep.streamURL,
                showID: show.id,
                episode: ep
            ))
        }
        return out
    }

    private func showID(from href: String) -> String? {
        let pattern = #"/tv/([^/?#]+)"#
        guard let range = href.range(of: pattern, options: .regularExpression) else { return nil }
        let match = href[range]
        return String(match.dropFirst(4))
    }
}

public struct NextUpEntry: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let posterURL: String
    public let streamURL: String
    public let showID: String
    public let episode: Episode
}

func flattenEpisodes(_ show: TVShow) -> [Episode] {
    (show.seasons ?? []).flatMap(\.episodes).sorted {
        $0.seasonNumber != $1.seasonNumber ? $0.seasonNumber < $1.seasonNumber : $0.episodeNumber < $1.episodeNumber
    }
}

func nextEpisode(after episodeID: String, in show: TVShow) -> Episode? {
    let eps = flattenEpisodes(show)
    guard let idx = eps.firstIndex(where: { $0.id == episodeID }) else { return nil }
    for i in (idx + 1)..<eps.count where eps[i].hasFile { return eps[i] }
    return nil
}
