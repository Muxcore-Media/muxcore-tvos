import MuxCoreAPI
import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var userdata: UserdataStore

    var body: some View {
        NavigationStack {
            let items = userdata.listFavorites()
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No favorites", systemImage: "heart", description: Text("Save titles from movie or TV detail pages."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 40)], spacing: 48) {
                            ForEach(items) { fav in
                                NavigationLink {
                                    if fav.kind == .tv { TVShowDetailView(showID: fav.id) }
                                    else { MovieDetailView(movieID: fav.id) }
                                } label: {
                                    PosterCard(title: fav.title, subtitle: fav.year.map(String.init) ?? "", imageURL: fav.posterURL ?? "", hasFile: false)
                                }.buttonStyle(.plain)
                            }
                        }.padding(72)
                    }
                }
            }
            .navigationTitle("Favorites")
        }
    }
}
