import Foundation
import MuxCoreAPI

@MainActor
enum PlaybackCoordinator {
    static func openMovie(_ movie: Movie, client: MuxCoreClient, userdata: UserdataStore) async throws -> PlaybackItem {
        let resolved = try await client.resolvePlayback(src: movie.streamURL)
        guard let url = client.absoluteURL(for: resolved.streamURL) else {
            throw MuxCoreAPIError.invalidURL
        }
        let start = userdata.prefs.playback.rememberPosition ? (userdata.getProgress(id: movie.id)?.positionSec ?? 0) : 0
        return PlaybackItem(
            url: url,
            title: movie.title,
            mediaID: movie.id,
            mediaKind: .movie,
            streamSrc: movie.streamURL,
            showID: nil,
            episode: nil,
            startPosition: start
        )
    }

    static func openEpisode(_ episode: Episode, show: TVShow, client: MuxCoreClient, userdata: UserdataStore) async throws -> PlaybackItem {
        let resolved = try await client.resolvePlayback(src: episode.streamURL)
        guard let url = client.absoluteURL(for: resolved.streamURL) else {
            throw MuxCoreAPIError.invalidURL
        }
        let start = userdata.prefs.playback.rememberPosition ? (userdata.getProgress(id: episode.id)?.positionSec ?? 0) : 0
        let label = "S\(String(format: "%02d", episode.seasonNumber))E\(String(format: "%02d", episode.episodeNumber))"
        return PlaybackItem(
            url: url,
            title: "\(show.title) \(label)",
            mediaID: episode.id,
            mediaKind: .episode,
            streamSrc: episode.streamURL,
            showID: show.id,
            episode: episode,
            startPosition: start
        )
    }
}
