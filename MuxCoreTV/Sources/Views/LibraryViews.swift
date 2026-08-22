import MuxCoreAPI
import SwiftUI

enum LibraryKind {
    case music, books, comics, audiobooks
}

enum LibraryDetailKind {
    case musicArtist, bookAuthor, none
}

struct LibraryListView: View {
    @EnvironmentObject private var appState: AppState
    let kind: LibraryKind
    let title: String
    let detail: LibraryDetailKind

    @State private var rows: [LibraryRow] = []
    @State private var message: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { ProgressView() }
                else if let message {
                    ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
                } else if rows.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
                } else {
                    List(rows) { row in
                        NavigationLink {
                            switch detail {
                            case .musicArtist: MusicArtistView(artistID: row.id)
                            case .bookAuthor: BookAuthorView(authorID: row.id)
                            case .none: Text(row.displayTitle)
                            }
                        } label: {
                            Text(row.displayTitle)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .task { await load() }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        let resp: LibraryListResponse?
        switch kind {
        case .music: resp = try? await client.listMusic()
        case .books: resp = try? await client.listBooks()
        case .comics: resp = try? await client.listComics()
        case .audiobooks: resp = try? await client.listAudiobooks()
        }
        if let resp {
            if resp.available == false {
                message = resp.message ?? "Coming soon"
                rows = []
            } else {
                rows = resp.items
            }
        }
    }
}

struct FilteredMoviesView: View {
    @EnvironmentObject private var appState: AppState
    let library: String
    let title: String
    @State private var movies: [Movie] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 40)], spacing: 48) {
                    ForEach(movies) { movie in
                        NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                            PosterCard(title: movie.title, subtitle: String(movie.year), imageURL: movie.posterURL, hasFile: movie.hasFile)
                        }.buttonStyle(.plain)
                    }
                }.padding(72)
            }
            .navigationTitle(title)
            .task {
                if let client = appState.client, let page = try? await client.listMovies(library: library) {
                    movies = page.items
                }
            }
        }
    }
}

struct MusicArtistView: View {
    @EnvironmentObject private var appState: AppState
    let artistID: String
    @State private var detail: MusicArtistDetail?

    var body: some View {
        Group {
            if let detail {
                List {
                    Section(detail.artist.name) {
                        ForEach(detail.albums) { album in
                            VStack(alignment: .leading) {
                                Text(album.title).font(.headline)
                                if let tracks = album.tracks {
                                    ForEach(tracks) { track in
                                        Text(track.title).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            } else { ProgressView() }
        }
        .navigationTitle(detail?.artist.name ?? "Artist")
        .task {
            if let client = appState.client {
                detail = try? await client.getMusicArtist(id: artistID)
            }
        }
    }
}

struct BookAuthorView: View {
    @EnvironmentObject private var appState: AppState
    let authorID: String
    @State private var detail: BookAuthorDetail?

    var body: some View {
        Group {
            if let detail {
                List(detail.books) { book in
                    Text(book.title)
                }
            } else { ProgressView() }
        }
        .navigationTitle(detail?.author.name ?? "Author")
        .task {
            if let client = appState.client {
                detail = try? await client.getBookAuthor(id: authorID)
            }
        }
    }
}
