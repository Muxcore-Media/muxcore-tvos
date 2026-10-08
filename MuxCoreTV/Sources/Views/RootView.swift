import MuxCoreAPI
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.isSignedIn {
                MainShellView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await appState.userdata.pullFromServer() }
            }
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore

    private var syncNotice: String? {
        switch userdata.syncStatus {
        case .failed, .unavailable: return userdata.syncStatus.message + " Open Settings for data sync."
        default: return nil
        }
    }

    private var primary: [NavDestination] {
        NavCatalog.primaryDestinations(caps: appState.capabilities)
    }

    private var overflow: [NavDestination] {
        NavCatalog.overflowDestinations(caps: appState.capabilities)
    }

    var body: some View {
        TabView {
            ForEach(primary) { dest in
                DestinationHost(kind: dest.kind)
                    .tabItem { Label(dest.title, systemImage: dest.systemImage) }
            }
            if !overflow.isEmpty {
                MoreView(destinations: overflow)
                    .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let syncNotice {
                Text(syncNotice)
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
    }
}

struct MoreView: View {
    let destinations: [NavDestination]

    var body: some View {
        NavigationStack {
            List(destinations) { dest in
                NavigationLink {
                    DestinationHost(kind: dest.kind)
                } label: {
                    Label(dest.title, systemImage: dest.systemImage)
                }
            }
            .navigationTitle("More")
        }
    }
}

struct DestinationHost: View {
    let kind: NavDestination.Kind

    var body: some View {
        switch kind {
        case .home: HomeView()
        case .search: SearchView()
        case .movies: MoviesView()
        case .tv: TVShowsView()
        case .music: LibraryListView(kind: .music, title: "Music", detail: .musicArtist)
        case .books: LibraryListView(kind: .books, title: "Books", detail: .bookAuthor)
        case .comics: LibraryListView(kind: .comics, title: "Comics", detail: .none)
        case .audiobooks: LibraryListView(kind: .audiobooks, title: "Audiobooks", detail: .none)
        case .musicVideos: FilteredMoviesView(library: "musicvideos", title: "Music Videos")
        case .homeVideos: FilteredMoviesView(library: "homevideos", title: "Home Videos")
        case .mixed: FilteredMoviesView(library: "mixed", title: "Mixed")
        case .collections: CollectionsView()
        case .studios: StudiosView()
        case .upcoming: UpcomingView()
        case .inProgress: InProgressView()
        case .playlists: PlaylistsView()
        case .queue: QueueView()
        case .livetv: LiveTVView()
        case .favorites: FavoritesView()
        case .settings: SettingsView()
        case .more: Text("More")
        }
    }
}
