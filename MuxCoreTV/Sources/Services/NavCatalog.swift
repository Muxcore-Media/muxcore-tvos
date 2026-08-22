import Foundation
import MuxCoreAPI

struct NavDestination: Identifiable, Hashable {
    enum Kind: Hashable {
        case home, search, movies, tv, music, books, comics, audiobooks
        case musicVideos, homeVideos, mixed, collections, studios, upcoming
        case inProgress, playlists, queue, livetv, favorites, settings, more
    }

    let kind: Kind
    let title: String
    let systemImage: String

    var id: String { String(describing: kind) }
}

enum NavCatalog {
    static func primaryDestinations(caps: Capabilities) -> [NavDestination] {
        var items: [NavDestination] = [
            .init(kind: .home, title: "Home", systemImage: "house.fill"),
            .init(kind: .search, title: "Search", systemImage: "magnifyingglass"),
        ]
        if caps.libraryEnabled(.movies) { items.append(.init(kind: .movies, title: "Movies", systemImage: "film.fill")) }
        if caps.libraryEnabled(.tv) { items.append(.init(kind: .tv, title: "TV Shows", systemImage: "tv.fill")) }
        if caps.libraryEnabled(.music) { items.append(.init(kind: .music, title: "Music", systemImage: "music.note")) }
        if caps.libraryEnabled(.books) { items.append(.init(kind: .books, title: "Books", systemImage: "book.fill")) }
        return items
    }

    static func overflowDestinations(caps: Capabilities) -> [NavDestination] {
        var items: [NavDestination] = []
        if caps.libraryEnabled(.comics) { items.append(.init(kind: .comics, title: "Comics", systemImage: "books.vertical.fill")) }
        if caps.libraryEnabled(.audiobooks) { items.append(.init(kind: .audiobooks, title: "Audiobooks", systemImage: "headphones")) }
        if caps.libraryEnabled(.musicvideos) { items.append(.init(kind: .musicVideos, title: "Music Videos", systemImage: "music.note.tv")) }
        if caps.libraryEnabled(.homevideos) { items.append(.init(kind: .homeVideos, title: "Home Videos", systemImage: "video.fill")) }
        if caps.featureEnabled(.mixed) { items.append(.init(kind: .mixed, title: "Mixed", systemImage: "square.grid.2x2.fill")) }
        if caps.featureEnabled(.collections) { items.append(.init(kind: .collections, title: "Collections", systemImage: "square.stack.3d.up.fill")) }
        if caps.featureEnabled(.studios) { items.append(.init(kind: .studios, title: "Studios", systemImage: "building.2.fill")) }
        if caps.featureEnabled(.upcoming) { items.append(.init(kind: .upcoming, title: "Upcoming", systemImage: "calendar")) }
        if caps.featureEnabled(.request) { items.append(.init(kind: .inProgress, title: "In Progress", systemImage: "clock.fill")) }
        if caps.featureEnabled(.playlists) { items.append(.init(kind: .playlists, title: "Playlists", systemImage: "music.note.list")) }
        if caps.featureEnabled(.queue) { items.append(.init(kind: .queue, title: "Queue", systemImage: "list.bullet")) }
        if caps.featureEnabled(.livetv) { items.append(.init(kind: .livetv, title: "Live TV", systemImage: "antenna.radiowaves.left.and.right")) }
        if caps.featureEnabled(.favorites) { items.append(.init(kind: .favorites, title: "Favorites", systemImage: "heart.fill")) }
        items.append(.init(kind: .settings, title: "Settings", systemImage: "gearshape.fill"))
        return items
    }
}

struct PlaybackItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let mediaID: String?
    let mediaKind: MediaKind
    let streamSrc: String
    let showID: String?
    let episode: Episode?
    let startPosition: Double
}
