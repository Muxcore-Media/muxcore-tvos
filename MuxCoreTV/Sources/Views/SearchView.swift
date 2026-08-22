import MuxCoreAPI
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var libraryResults: [SearchResult] = []
    @State private var remoteResults: [SearchResult] = []
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Search movies and TV…", text: $query)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 72)
                    .onSubmit { Task { await runSearch() } }

                if isLoading { ProgressView() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if !libraryResults.isEmpty {
                            section("In your library", libraryResults, requestable: false)
                        }
                        if !remoteResults.isEmpty {
                            section("Request", remoteResults, requestable: true)
                        }
                        if query.count >= 2, !isLoading, libraryResults.isEmpty, remoteResults.isEmpty {
                            Text("No results for “\(query)”").foregroundStyle(.secondary).padding(.horizontal, 72)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .alert("Search", isPresented: .constant(message != nil)) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ results: [SearchResult], requestable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold()).padding(.horizontal, 72)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, row in
                    SearchResultCard(result: row, requestable: requestable) { msg in message = msg }
                }
            }.padding(.horizontal, 72)
        }
    }

    private func runSearch() async {
        guard let client = appState.client, query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await client.search(query: query)
            libraryResults = all.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
            remoteResults = all
        } catch {
            message = error.localizedDescription
        }
    }
}

struct SearchResultCard: View {
    @EnvironmentObject private var appState: AppState
    let result: SearchResult
    let requestable: Bool
    let onMessage: (String) -> Void
    @State private var requested = false

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: result.poster)) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Rectangle().fill(.gray.opacity(0.2)) }
            }
            .frame(width: 80, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(result.title).font(.headline)
                Text("\(result.year) · \(result.mediaType.uppercased())").font(.caption).foregroundStyle(.secondary)
                if requestable {
                    Button(requested ? "Requested" : "Request") {
                        Task { await request() }
                    }.disabled(requested)
                } else {
                    NavigationLink("Open") {
                        if result.mediaType == "tv" {
                            DiscoverDetailView(type: "tv", tmdbID: result.id)
                        } else {
                            DiscoverDetailView(type: "movie", tmdbID: result.id)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func request() async {
        guard let client = appState.client else { return }
        do {
            _ = try await client.requestTitle(RequestTitleInput(
                title: result.title,
                year: result.year,
                overview: result.overview,
                poster: result.poster,
                mediaType: result.mediaType,
                tmdbId: result.mediaType == "movie" || result.mediaType == "tv" ? result.id : nil,
                musicbrainzId: result.musicbrainzID,
                releaseGroupId: result.releaseGroupID,
                recordingId: result.recordingID,
                artistName: result.artistName,
                albumTitle: result.albumTitle
            ))
            requested = true
            onMessage("Request submitted for \(result.title)")
        } catch {
            onMessage(error.localizedDescription)
        }
    }
}
