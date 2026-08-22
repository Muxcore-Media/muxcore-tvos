import Foundation
import MuxCoreAPI

@MainActor
final class UserdataStore: ObservableObject {
    @Published private(set) var progress: [String: ProgressEntry] = [:]
    @Published private(set) var favorites: [String: FavoriteEntry] = [:]
    @Published private(set) var prefs: UserPreferences = .defaults
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var serverAuthoritative = false

    private let defaults = UserDefaults.standard
    private var client: MuxCoreClient?

    func bind(client: MuxCoreClient?) {
        self.client = client
        loadLocal()
    }

    func loadLocal() {
        progress = decode([String: ProgressEntry].self, key: "muxcore.progress") ?? [:]
        favorites = decode([String: FavoriteEntry].self, key: "muxcore.favorites") ?? [:]
        prefs = decode(UserPreferences.self, key: "muxcore.prefs") ?? .defaults
        playlists = decode([Playlist].self, key: "muxcore.playlists") ?? []
        queue = decode([QueueItem].self, key: "muxcore.queue") ?? []
    }

    func pullFromServer() async {
        guard let client else { return }
        do {
            let blob = try await client.getUserdata()
            if let p = blob.progress { progress = mergeProgress(local: progress, server: p) }
            if let f = blob.favorites { favorites = f }
            if let pr = blob.prefs { prefs = pr }
            if let pl = blob.playlists { playlists = pl }
            if let q = blob.queue { queue = q }
            serverAuthoritative = true
            persistLocal()
        } catch {
            serverAuthoritative = false
        }
    }

    func pushToServer() async {
        guard let client else { return }
        do {
            let blob = UserdataBlob(progress: progress, favorites: favorites, prefs: prefs, playlists: playlists, queue: queue)
            let merged = try await client.putUserdata(blob)
            if let p = merged.progress { progress = p }
            if let f = merged.favorites { favorites = f }
            if let pr = merged.prefs { prefs = pr }
            if let pl = merged.playlists { playlists = pl }
            if let q = merged.queue { queue = q }
            serverAuthoritative = true
            persistLocal()
        } catch { /* offline */ }
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
        if favorites[entry.id] != nil {
            favorites.removeValue(forKey: entry.id)
            persistLocal()
            Task { await pushToServer() }
            return false
        }
        favorites[entry.id] = entry
        persistLocal()
        Task { await pushToServer() }
        return true
    }

    func getProgress(id: String) -> ProgressEntry? { progress[id] }

    func upsertProgress(_ entry: ProgressEntry) {
        var next = entry
        next.updatedAt = ISO8601DateFormatter().string(from: Date())
        if next.watched != true, next.durationSec > 0, next.positionSec / next.durationSec >= 0.92 {
            next.watched = true
            next.positionSec = 0
        }
        progress[next.id] = next
        persistLocal()
        Task { await pushToServer() }
    }

    func updatePreferences(_ patch: (inout UserPreferences) -> Void) {
        var next = prefs
        patch(&next)
        prefs = next
        persistLocal()
        Task { await pushToServer() }
    }

    func saveQueue(_ items: [QueueItem]) {
        queue = items
        persistLocal()
        Task { await pushToServer() }
    }

    func enqueue(_ item: QueueItem) {
        queue.removeAll { $0.id == item.id }
        queue.append(item)
        saveQueue(queue)
    }

    func dequeue(id: String) {
        queue.removeAll { $0.id == id }
        saveQueue(queue)
    }

    func clearQueue() { saveQueue([]) }

    func savePlaylists(_ items: [Playlist]) {
        playlists = items
        persistLocal()
        Task { await pushToServer() }
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

    private func mergeProgress(local: [String: ProgressEntry], server: [String: ProgressEntry]) -> [String: ProgressEntry] {
        var out = local
        for (id, entry) in server {
            if let cur = out[id], cur.updatedAt >= entry.updatedAt { continue }
            out[id] = entry
        }
        return out
    }

    private func persistLocal() {
        encode(progress, key: "muxcore.progress")
        encode(favorites, key: "muxcore.favorites")
        encode(prefs, key: "muxcore.prefs")
        encode(playlists, key: "muxcore.playlists")
        encode(queue, key: "muxcore.queue")
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func decode<T: Decodable>(_: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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
