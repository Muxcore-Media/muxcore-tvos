import MuxCoreAPI
import SwiftUI

enum ShelfRowItem: Identifiable {
    case movie(Movie)
    case tv(TVShow)
    case favorite(FavoriteEntry)
    case progress(ProgressEntry)
    case nextUp(NextUpEntry)

    var id: String {
        switch self {
        case .movie(let m): return "m-\(m.id)"
        case .tv(let s): return "t-\(s.id)"
        case .favorite(let f): return "f-\(f.id)"
        case .progress(let p): return "p-\(p.id)"
        case .nextUp(let n): return "n-\(n.id)"
        }
    }
}

struct ShelfView: View {
    let title: String
    let items: [ShelfRowItem]
    var onPlayProgress: ((ProgressEntry) -> Void)?
    var onPlayNextUp: ((NextUpEntry) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.bold()).padding(.horizontal, 72)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(items) { item in
                        switch item {
                        case .movie(let movie):
                            NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                                PosterCard(title: movie.title, subtitle: String(movie.year), imageURL: movie.posterURL, hasFile: movie.hasFile).frame(width: 220)
                            }.buttonStyle(.plain)
                        case .tv(let show):
                            NavigationLink { TVShowDetailView(showID: show.id) } label: {
                                PosterCard(title: show.title, subtitle: String(show.year), imageURL: show.posterURL, hasFile: show.hasFile).frame(width: 220)
                            }.buttonStyle(.plain)
                        case .favorite(let fav):
                            NavigationLink {
                                if fav.kind == .tv { TVShowDetailView(showID: fav.id) } else { MovieDetailView(movieID: fav.id) }
                            } label: {
                                PosterCard(title: fav.title, subtitle: fav.year.map(String.init) ?? "", imageURL: fav.posterURL ?? "", hasFile: false).frame(width: 220)
                            }.buttonStyle(.plain)
                        case .progress(let p):
                            Button { onPlayProgress?(p) } label: {
                                VStack(alignment: .leading) {
                                    PosterCard(title: p.title, subtitle: "Resume", imageURL: p.posterURL ?? "", hasFile: true).frame(width: 220)
                                }
                            }.buttonStyle(.plain)
                        case .nextUp(let n):
                            Button { onPlayNextUp?(n) } label: {
                                PosterCard(title: n.title, subtitle: "Next up", imageURL: n.posterURL, hasFile: true).frame(width: 220)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 72)
            }
        }
    }
}
