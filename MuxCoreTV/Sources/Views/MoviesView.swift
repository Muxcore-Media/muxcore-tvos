import MuxCoreAPI
import SwiftUI

struct MoviesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var movies: [Movie] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 40)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(movies) { movie in
                        NavigationLink {
                            MovieDetailView(movieID: movie.id)
                        } label: {
                            PosterCard(title: movie.title, subtitle: String(movie.year), imageURL: movie.posterURL, hasFile: movie.hasFile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(72)
            }
            .overlay { if isLoading { ProgressView() } }
            .navigationTitle("Movies")
            .task { await load() }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.listMovies(pageSize: 120)
            movies = page.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
