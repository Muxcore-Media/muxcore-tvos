import MuxCoreAPI
import SwiftUI

struct TVShowDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore
    let showID: String

    @State private var show: TVShow?
    @State private var playbackItem: PlaybackItem?
    @State private var isFavorite = false
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let show { detail(show) }
            else if isLoading { ProgressView("Loading…") }
            else { ContentUnavailableView("Show not found", systemImage: "tv") }
        }
        .task { await load() }
        .fullScreenCover(item: $playbackItem) { PlayerView(item: $0) }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private func detail(_ show: TVShow) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .top, spacing: 48) {
                AsyncImage(url: URL(string: show.posterURL)) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() }
                    else { Rectangle().fill(.gray.opacity(0.25)) }
                }.frame(width: 280).clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 16) {
                    Text(show.title).font(.largeTitle.bold())
                    Text(String(show.year)).foregroundStyle(.secondary)
                    Text(show.overview).font(.title3).foregroundStyle(.secondary).lineLimit(5)
                    Button(isFavorite ? "Unfavorite" : "Favorite") { toggleFavorite(show) }
                }
            }

            if let seasons = show.seasons {
                Text("Episodes").font(.title2.bold())
                ForEach(seasons) { season in
                    Text(season.name).font(.headline)
                    ForEach(season.episodes.filter(\.hasFile)) { episode in
                        Button { Task { await play(episode, show: show) } } label: {
                            HStack {
                                Text("S\(episode.seasonNumber)E\(episode.episodeNumber)").font(.caption.monospacedDigit()).frame(width: 72, alignment: .leading)
                                Text(episode.title)
                                Spacer()
                                Image(systemName: "play.circle.fill")
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
        }.padding(72)
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            show = try await client.getTVShow(id: showID)
            isFavorite = userdata.isFavorite(id: showID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func play(_ episode: Episode, show: TVShow) async {
        guard let client = appState.client else { return }
        do {
            playbackItem = try await PlaybackCoordinator.openEpisode(episode, show: show, client: client, userdata: userdata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite(_ show: TVShow) {
        isFavorite = userdata.toggleFavorite(FavoriteEntry(id: show.id, kind: .tv, title: show.title, posterURL: show.posterURL, href: "/tv/\(show.id)", year: show.year))
    }
}
