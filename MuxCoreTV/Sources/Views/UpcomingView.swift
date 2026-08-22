import MuxCoreAPI
import SwiftUI

struct UpcomingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rows: [(day: String, show: TVShow, episode: Episode)] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { ProgressView() }
                else if rows.isEmpty {
                    ContentUnavailableView("No upcoming episodes", systemImage: "calendar")
                } else {
                    List {
                        ForEach(rows, id: \.episode.id) { row in
                            VStack(alignment: .leading) {
                                Text(row.show.title).font(.headline)
                                Text("S\(row.episode.seasonNumber)E\(row.episode.episodeNumber) · \(row.day)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upcoming")
            .task { await load() }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        guard let list = try? await client.listTVShows(pageSize: 40) else { return }
        var out: [(String, TVShow, Episode)] = []
        let now = Date()
        let horizon = now.addingTimeInterval(120 * 24 * 3600)
        for s in list.items.prefix(20) {
            let show = (try? await client.getTVShow(id: s.id)) ?? s
            for season in show.seasons ?? [] {
                for ep in season.episodes {
                    guard let air = ep.airDate, let date = ISO8601DateFormatter().date(from: air + "T00:00:00Z") ?? parseDate(air) else { continue }
                    if date >= now.addingTimeInterval(-14 * 24 * 3600), date <= horizon {
                        out.append((String(air.prefix(10)), show, ep))
                    }
                }
            }
        }
        rows = out.sorted { $0.0 < $1.0 }
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
