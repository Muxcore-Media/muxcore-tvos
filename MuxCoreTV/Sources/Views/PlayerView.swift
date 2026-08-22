import AVKit
import CoreMedia
import MuxCoreAPI
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore
    let item: PlaybackItem

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var subtitleTracks: [PlaybackSubtitleTrack] = []
    @State private var upNext: PlaybackItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView("Preparing playback…")
            }

            Button {
                saveProgress()
                player?.pause()
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle.fill").font(.title2).padding()
            }.buttonStyle(.plain)
        }
        .onAppear { Task { await setup() } }
        .onDisappear { teardown() }
        .fullScreenCover(item: $upNext) { next in
            PlayerView(item: next)
        }
    }

    private func setup() async {
        let avPlayer = AVPlayer(url: item.url)
        if item.startPosition > 1 {
            avPlayer.seek(to: CMTime(seconds: item.startPosition, preferredTimescale: 600))
        }
        player = avPlayer
        avPlayer.play()

        if userdata.prefs.subtitles.enabled, let client = appState.client {
            subtitleTracks = (try? await client.fetchPlaybackSubtitles(src: item.streamSrc)) ?? []
        }

        let interval = CMTime(seconds: 5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard let duration = avPlayer.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
            guard userdata.prefs.playback.rememberPosition, let mediaID = item.mediaID else { return }
            let entry = ProgressEntry(
                id: mediaID,
                kind: item.mediaKind,
                title: item.title,
                posterURL: nil,
                href: item.mediaKind == .episode ? "/tv/\(item.showID ?? "")" : "/movies/\(mediaID)",
                streamURL: item.streamSrc,
                positionSec: time.seconds,
                durationSec: duration,
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                watched: nil
            )
            userdata.upsertProgress(entry)
        }
    }

    private func saveProgress() {
        guard let player, let mediaID = item.mediaID else { return }
        let pos = player.currentTime().seconds
        let dur = player.currentItem?.duration.seconds ?? 0
        guard dur.isFinite, dur > 0 else { return }
        userdata.upsertProgress(ProgressEntry(
            id: mediaID, kind: item.mediaKind, title: item.title, posterURL: nil,
            href: item.mediaKind == .episode ? "/tv/\(item.showID ?? "")" : "/movies/\(mediaID)",
            streamURL: item.streamSrc, positionSec: pos, durationSec: dur,
            updatedAt: ISO8601DateFormatter().string(from: Date()), watched: nil
        ))

        if userdata.prefs.playback.autoplayNext, item.mediaKind == .episode, let showID = item.showID, let ep = item.episode {
            Task { await offerUpNext(showID: showID, after: ep) }
        }
    }

    private func offerUpNext(showID: String, after episode: Episode) async {
        guard let client = appState.client, let show = try? await client.getTVShow(id: showID),
              let next = nextEpisode(after: episode.id, in: show), next.hasFile else { return }
        if let item = try? await PlaybackCoordinator.openEpisode(next, show: show, client: client, userdata: userdata) {
            upNext = item
        }
    }

    private func teardown() {
        if let player, let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
}
