import Foundation
import MuxCoreAPI

enum Acquisition {
    static func isWatchable(_ item: Movie) -> Bool { item.hasFile }
    static func isWatchable(_ item: TVShow) -> Bool { item.hasFile }

    static func isActiveRequestStatus(_ status: String) -> Bool {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !s.isEmpty && s != "available"
    }

    static func requestStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "downloading": return "Downloading"
        case "searching": return "Searching"
        case "queued": return "Queued"
        case "added": return "In library"
        case "requested": return "Requested"
        case "workflow": return "Pending approval"
        case "available": return "Available"
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func requestPhase(_ status: String) -> String {
        switch status.lowercased() {
        case "downloading": return "downloading"
        case "searching", "queued": return "searching"
        default: return "requested"
        }
    }

    enum InProgressEntry: Identifiable {
        case request(MediaRequest)
        case libraryMovie(Movie)
        case libraryTV(TVShow)

        var id: String {
            switch self {
            case .request(let r): return "req-\(r.id)"
            case .libraryMovie(let m): return "lib-movie-\(m.id)"
            case .libraryTV(let s): return "lib-tv-\(s.id)"
            }
        }

        var title: String {
            switch self {
            case .request(let r): return r.title
            case .libraryMovie(let m): return m.title
            case .libraryTV(let s): return s.title
            }
        }

        var status: String {
            switch self {
            case .request(let r): return r.status
            case .libraryMovie, .libraryTV: return "added"
            }
        }
    }

    static func mergeInProgress(requests: [MediaRequest], movies: [Movie], shows: [TVShow]) -> [InProgressEntry] {
        var keys = Set<String>()
        var out: [InProgressEntry] = requests.filter { isActiveRequestStatus($0.status) }.map { .request($0) }
        for r in requests where isActiveRequestStatus(r.status) {
            keys.insert(requestKey(r))
        }
        for m in movies where !isWatchable(m) {
            let key = m.id.isEmpty ? "movie:\(m.title.lowercased())" : "movie:\(m.id)"
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            out.append(.libraryMovie(m))
        }
        for s in shows where !isWatchable(s) {
            let key = s.id.isEmpty ? "tv:\(s.title.lowercased())" : "tv:\(s.id)"
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            out.append(.libraryTV(s))
        }
        return out.sorted { rank($0) < rank($1) }
    }

    static func groupByPhase(_ entries: [InProgressEntry]) -> (downloading: [InProgressEntry], searching: [InProgressEntry], requested: [InProgressEntry]) {
        var downloading: [InProgressEntry] = []
        var searching: [InProgressEntry] = []
        var requested: [InProgressEntry] = []
        for e in entries {
            switch requestPhase(e.status) {
            case "downloading": downloading.append(e)
            case "searching": searching.append(e)
            default: requested.append(e)
            }
        }
        return (downloading, searching, requested)
    }

    private static func requestKey(_ r: MediaRequest) -> String {
        if !r.itemId.isEmpty { return "\(r.itemType):\(r.itemId)" }
        if r.tmdbId > 0 { return "\(r.itemType):tmdb:\(r.tmdbId)" }
        return "\(r.itemType):\(r.title.lowercased())"
    }

    private static func rank(_ entry: InProgressEntry) -> Int {
        switch requestPhase(entry.status) {
        case "downloading": return 0
        case "searching": return 1
        default: return 2
        }
    }
}
