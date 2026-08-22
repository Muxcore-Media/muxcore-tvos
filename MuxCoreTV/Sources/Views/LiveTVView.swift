import MuxCoreAPI
import SwiftUI

struct LiveTVView: View {
    @EnvironmentObject private var appState: AppState
    @State private var data: LiveTVResponse?
    @State private var playbackItem: PlaybackItem?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    List {
                        Section("Channels") {
                            ForEach(data.channels) { ch in
                                Button(ch.name) { playChannel(ch) }
                            }
                        }
                        if let timers = data.timers, !timers.isEmpty {
                            Section("Timers") {
                                ForEach(timers) { t in
                                    Text("\(t.title) · \(t.start)")
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Live TV")
            .task { await load() }
            .fullScreenCover(item: $playbackItem) { PlayerView(item: $0) }
            .alert("Live TV", isPresented: .constant(message != nil)) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        data = try? await client.listLiveTV()
    }

    private func playChannel(_ ch: LiveTVChannel) {
        guard let urlStr = ch.url, let client = appState.client, let url = client.absoluteURL(for: urlStr) else {
            message = "Channel has no stream URL"
            return
        }
        playbackItem = PlaybackItem(url: url, title: ch.name, mediaID: ch.id, mediaKind: .other, streamSrc: urlStr, showID: nil, episode: nil, startPosition: 0)
    }
}
