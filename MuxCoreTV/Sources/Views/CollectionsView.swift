import MuxCoreAPI
import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var movies: [Movie] = []
    @State private var serverCols: [CollectionSummary] = []
    @State private var detail: CollectionDetail?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if let detail {
                        Text(detail.name).font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 40)], spacing: 40) {
                            ForEach(detail.movies) { movie in
                                NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                                    PosterCard(title: movie.title, subtitle: String(movie.year), imageURL: movie.posterURL, hasFile: movie.hasFile)
                                }.buttonStyle(.plain)
                            }
                        }
                        Button("Close collection") { self.detail = nil }
                    }

                    if !serverCols.isEmpty {
                        Text("Box sets").font(.title3.bold())
                        ForEach(serverCols) { col in
                            Button("\(col.name) (\(col.movieCount))") {
                                Task { await openCollection(col.id) }
                            }
                        }
                    }

                    ForEach(genreCollections(), id: \.name) { group in
                        Text(group.name).font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 40)], spacing: 40) {
                            ForEach(group.movies) { movie in
                                NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                                    PosterCard(title: movie.title, subtitle: String(movie.year), imageURL: movie.posterURL, hasFile: movie.hasFile)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(72)
            }
            .overlay { if isLoading { ProgressView() } }
            .navigationTitle("Collections")
            .task { await load() }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        if let list = try? await client.listMovies(pageSize: 200) { movies = list.items }
        if let cols = try? await client.listCollections() { serverCols = cols }
    }

    private func openCollection(_ id: String) async {
        guard let client = appState.client else { return }
        detail = try? await client.getCollection(id: id)
    }

    private func genreCollections() -> [(name: String, movies: [Movie])] {
        var map: [String: [Movie]] = [:]
        for m in movies {
            for g in m.genres.isEmpty ? ["Uncategorized"] : m.genres {
                map[g, default: []].append(m)
            }
        }
        return map.filter { $0.value.count >= 2 }.sorted { $0.key < $1.key }.map { ($0.key, Array($0.value.prefix(24))) }
    }
}
