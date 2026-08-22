import MuxCoreAPI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore
    @State private var movies: [Movie] = []
    @State private var shows: [TVShow] = []
    @State private var nextUp: [NextUpEntry] = []
    @State private var inProgressCount = 0
    @State private var playbackItem: PlaybackItem?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    if let hero = movies.first(where: { $0.hasFile }) ?? movies.first {
                        HeroBanner(movie: hero)
                    }

                    if userdata.prefs.home.showContinueWatching {
                        let progress = userdata.continueWatching()
                        if !progress.isEmpty {
                            ShelfView(title: "Continue watching", items: progress.map { .progress($0) }, onPlayProgress: playProgress)
                        }
                    }

                    if userdata.prefs.home.showNextUp, !nextUp.isEmpty {
                        ShelfView(title: "Next up", items: nextUp.map { .nextUp($0) }, onPlayNextUp: playNextUp)
                    }

                    let recommended = movies.filter { $0.hasFile && $0.voteAverage > 0 }.sorted { $0.voteAverage > $1.voteAverage }.prefix(16)
                    if !recommended.isEmpty {
                        ShelfView(title: "Recommended", items: recommended.map { .movie($0) })
                    }

                    if userdata.prefs.home.showFavorites {
                        let favs = userdata.listFavorites().prefix(16)
                        if !favs.isEmpty {
                            ShelfView(title: "Favorites", items: favs.map { .favorite($0) })
                        }
                    }

                    if !movies.isEmpty {
                        ShelfView(title: "Movies", items: movies.prefix(12).map { .movie($0) })
                    }
                    if !shows.isEmpty {
                        ShelfView(title: "TV Shows", items: shows.prefix(12).map { .tv($0) })
                    }

                    if userdata.prefs.home.showRecentRequests, inProgressCount > 0 {
                        Text("\(inProgressCount) title(s) in progress — open More → In Progress")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 72)
                    }
                }
                .padding(.vertical, 40)
            }
            .overlay { if isLoading { ProgressView("Loading library…") } }
            .navigationTitle("Home")
            .task { await load() }
            .fullScreenCover(item: $playbackItem) { item in
                PlayerView(item: item)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        await userdata.pullFromServer()
        do {
            async let moviePage = client.listMovies(pageSize: 24)
            async let tvPage = client.listTVShows(pageSize: 24)
            async let requests = client.listRequests()
            let (m, t, r) = try await (moviePage, tvPage, requests)
            movies = m.items
            shows = t.items
            inProgressCount = Acquisition.mergeInProgress(requests: r, movies: m.items, shows: t.items).count
            nextUp = await userdata.resolveNextUp { try await client.getTVShow(id: $0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func playProgress(_ entry: ProgressEntry) {
        guard let client = appState.client, let src = entry.streamURL, let url = client.absoluteURL(for: src) else { return }
        playbackItem = PlaybackItem(url: url, title: entry.title, mediaID: entry.id, mediaKind: entry.kind, streamSrc: src, showID: nil, episode: nil, startPosition: entry.positionSec)
    }

    private func playNextUp(_ entry: NextUpEntry) {
        guard let client = appState.client, let url = client.absoluteURL(for: entry.streamURL) else { return }
        playbackItem = PlaybackItem(url: url, title: entry.title, mediaID: entry.id, mediaKind: .episode, streamSrc: entry.streamURL, showID: entry.showID, episode: entry.episode, startPosition: 0)
    }
}

struct HeroBanner: View {
    let movie: Movie

    var body: some View {
        NavigationLink { MovieDetailView(movieID: movie.id) } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: movie.backdropURL ?? movie.posterURL)) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { Rectangle().fill(.gray.opacity(0.3)) }
                }
                .frame(height: 420).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom).frame(height: 420)
                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.title).font(.largeTitle.bold())
                    Text("\(movie.year) · \(movie.runtime)m").foregroundStyle(.secondary)
                    if movie.hasFile { Label("Play", systemImage: "play.fill").font(.headline) }
                }.padding(48)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 72)
        }.buttonStyle(.plain)
    }
}
