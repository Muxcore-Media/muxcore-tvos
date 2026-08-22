import MuxCoreAPI
import SwiftUI

struct InProgressView: View {
    @EnvironmentObject private var appState: AppState
    @State private var entries: [Acquisition.InProgressEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { ProgressView() }
                else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding()
                } else if entries.isEmpty {
                    ContentUnavailableView("Nothing in progress", systemImage: "clock", description: Text("Requested titles appear here until ready."))
                } else {
                    let grouped = Acquisition.groupByPhase(entries)
                    List {
                        phaseSection("Downloading", grouped.downloading)
                        phaseSection("Searching", grouped.searching)
                        phaseSection("Requested", grouped.requested)
                    }
                }
            }
            .navigationTitle("In Progress")
            .task { await load() }
        }
    }

    @ViewBuilder
    private func phaseSection(_ title: String, _ items: [Acquisition.InProgressEntry]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(.headline)
                        Text(Acquisition.requestStatusLabel(entry.status)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let requests = client.listRequests()
            async let movies = client.listMovies(pageSize: 200)
            async let shows = client.listTVShows(pageSize: 200)
            let (r, m, t) = try await (requests, movies, shows)
            entries = Acquisition.mergeInProgress(requests: r, movies: m.items, shows: t.items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
