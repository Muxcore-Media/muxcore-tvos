import MuxCoreAPI
import SwiftUI

struct StudiosView: View {
    @EnvironmentObject private var appState: AppState
    @State private var movies: [Movie] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                ForEach(studioGroups(), id: \.name) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(group.name).font(.title3.bold()).padding(.horizontal, 72)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 24) {
                                ForEach(group.movies) { movie in
                                    NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                                        PosterCard(title: movie.title, subtitle: String(movie.year), imageURL: movie.posterURL, hasFile: movie.hasFile).frame(width: 200)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, 72)
                        }
                    }
                }
            }
            .navigationTitle("Studios")
            .task {
                if let client = appState.client, let page = try? await client.listMovies(pageSize: 200) {
                    movies = page.items
                }
            }
        }
    }

    private func studioGroups() -> [(name: String, movies: [Movie])] {
        var map: [String: [Movie]] = [:]
        for m in movies {
            let key = m.collectionName ?? m.genres.first ?? "Other"
            map[key, default: []].append(m)
        }
        return map.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
