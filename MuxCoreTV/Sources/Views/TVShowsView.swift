import MuxCoreAPI
import SwiftUI

struct TVShowsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var shows: [TVShow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 40)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(shows) { show in
                        NavigationLink {
                            TVShowDetailView(showID: show.id)
                        } label: {
                            PosterCard(title: show.title, subtitle: String(show.year), imageURL: show.posterURL, hasFile: show.hasFile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(72)
            }
            .overlay { if isLoading { ProgressView() } }
            .navigationTitle("TV Shows")
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
            let page = try await client.listTVShows(pageSize: 120)
            shows = page.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
