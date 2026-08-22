import MuxCoreAPI
import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var userdata: UserdataStore
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    TextField("New playlist", text: $newName)
                    Button("Create") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        var list = userdata.playlists
                        list.append(Playlist(id: UUID().uuidString, name: name, itemIds: []))
                        userdata.savePlaylists(list)
                        newName = ""
                    }
                }.padding(.horizontal, 72)

                if userdata.playlists.isEmpty {
                    ContentUnavailableView("No playlists", systemImage: "music.note.list")
                } else {
                    List(userdata.playlists) { playlist in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(playlist.name).font(.headline)
                            Text("\(playlist.itemIds.count) items").font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(userdata.listFavorites()) { fav in
                                        Button("+ \(fav.title)") {
                                            var list = userdata.playlists
                                            guard let idx = list.firstIndex(where: { $0.id == playlist.id }) else { return }
                                            if !list[idx].itemIds.contains(fav.id) {
                                                list[idx].itemIds.append(fav.id)
                                                userdata.savePlaylists(list)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playlists")
        }
    }
}
