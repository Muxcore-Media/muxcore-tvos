import MuxCoreAPI
import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore
    let movieID: String

    @State private var movie: Movie?
    @State private var playbackItem: PlaybackItem?
    @State private var isFavorite = false
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let movie { detail(movie) }
            else if isLoading { ProgressView("Loading…") }
            else { ContentUnavailableView("Movie not found", systemImage: "film") }
        }
        .task { await load() }
        .fullScreenCover(item: $playbackItem) { PlayerView(item: $0) }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private func detail(_ movie: Movie) -> some View {
        HStack(alignment: .top, spacing: 48) {
            AsyncImage(url: URL(string: movie.posterURL)) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFit() }
                else { Rectangle().fill(.gray.opacity(0.25)) }
            }.frame(width: 320).clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 20) {
                Text(movie.title).font(.largeTitle.bold())
                Text("\(movie.year) · \(movie.runtime) min").foregroundStyle(.secondary)
                Text(movie.overview).font(.title3).lineLimit(6).foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    if movie.hasFile {
                        Button { Task { await play(movie, fromStart: false) } } label: {
                            Label(progressLabel(movie), systemImage: "play.fill")
                        }.buttonStyle(.borderedProminent)

                        Button("From beginning") { Task { await play(movie, fromStart: true) } }
                    }
                    Button(isFavorite ? "Unfavorite" : "Favorite") { toggleFavorite(movie) }
                    Button("Add to queue") { enqueue(movie) }
                }
            }
            Spacer(minLength: 0)
        }.padding(72)
    }

    private func progressLabel(_ movie: Movie) -> String {
        if let p = userdata.getProgress(id: movie.id), p.positionSec > 5, p.watched != true { return "Resume" }
        return "Play"
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            movie = try await client.getMovie(id: movieID)
            isFavorite = userdata.isFavorite(id: movieID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func play(_ movie: Movie, fromStart: Bool) async {
        guard let client = appState.client else { return }
        do {
            var item = try await PlaybackCoordinator.openMovie(movie, client: client, userdata: userdata)
            if fromStart { item = PlaybackItem(url: item.url, title: item.title, mediaID: item.mediaID, mediaKind: item.mediaKind, streamSrc: item.streamSrc, showID: nil, episode: nil, startPosition: 0) }
            playbackItem = item
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite(_ movie: Movie) {
        isFavorite = userdata.toggleFavorite(FavoriteEntry(id: movie.id, kind: .movie, title: movie.title, posterURL: movie.posterURL, href: "/movies/\(movie.id)", year: movie.year))
    }

    private func enqueue(_ movie: Movie) {
        userdata.enqueue(QueueItem(id: movie.id, kind: .movie, title: movie.title, href: "/movies/\(movie.id)", streamURL: movie.streamURL, posterURL: movie.posterURL))
    }
}
