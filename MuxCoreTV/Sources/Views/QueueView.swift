import MuxCoreAPI
import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var userdata: UserdataStore

    var body: some View {
        NavigationStack {
            let display = userdata.queue.isEmpty
                ? seededQueue()
                : userdata.queue

            Group {
                if display.isEmpty {
                    ContentUnavailableView("Queue empty", systemImage: "list.bullet", description: Text("Play something or add favorites."))
                } else {
                    List(Array(display.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text("\(index + 1).").foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(item.kind.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if userdata.queue.contains(where: { $0.id == item.id }) {
                                Button("Remove") { userdata.dequeue(id: item.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                if !userdata.queue.isEmpty {
                    Button("Clear") { userdata.clearQueue() }
                }
            }
        }
    }

    private func seededQueue() -> [QueueItem] {
        let fromProgress = userdata.continueWatching(20).map {
            QueueItem(id: $0.id, kind: $0.kind, title: $0.title, href: $0.href, streamURL: $0.streamURL, posterURL: $0.posterURL)
        }
        let fromFav = userdata.listFavorites().prefix(20).map {
            QueueItem(id: $0.id, kind: $0.kind, title: $0.title, href: $0.href, posterURL: $0.posterURL)
        }
        return fromProgress + fromFav
    }
}
