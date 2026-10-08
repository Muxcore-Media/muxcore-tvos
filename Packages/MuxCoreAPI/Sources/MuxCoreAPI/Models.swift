import Foundation

// MARK: - Capabilities

public enum LibraryKey: String, Codable, CaseIterable, Sendable {
    case movies, tv, music, books, comics, audiobooks, homevideos, musicvideos
}

public enum FeatureKey: String, Codable, CaseIterable, Sendable {
    case search, request, collections, studios, upcoming, mixed, livetv
    case quickconnect, playlists, queue, favorites
}

public struct Capabilities: Codable, Sendable {
    public var libraries: [String: Bool]
    public var features: [String: Bool]

    public init(libraries: [String: Bool] = [:], features: [String: Bool] = [:]) {
        self.libraries = libraries
        self.features = features
    }

    public static let defaults = Capabilities(
        libraries: [
            LibraryKey.movies.rawValue: true,
            LibraryKey.tv.rawValue: true,
        ],
        features: FeatureKey.allCases.reduce(into: [String: Bool]()) { $0[$1.rawValue] = true }
    )

    public func libraryEnabled(_ key: LibraryKey) -> Bool { libraries[key.rawValue] == true }
    public func featureEnabled(_ key: FeatureKey) -> Bool { features[key.rawValue] == true }
}

// MARK: - Media

public struct Movie: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let year: Int
    public let overview: String
    public let runtime: Int
    public let voteAverage: Double
    public let genres: [String]
    public let posterURL: String
    public let hasFile: Bool
    public let streamURL: String
    public let createdAt: String?
    public let tmdbID: Int?
    public let backdropURL: String?
    public let tagline: String?
    public let status: String?
    public let collectionID: Int?
    public let collectionName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, runtime, genres, status, tagline
        case voteAverage = "vote_average"
        case posterURL = "poster_url"
        case hasFile = "has_file"
        case streamURL = "stream_url"
        case createdAt = "created_at"
        case tmdbID = "tmdb_id"
        case backdropURL = "backdrop_url"
        case collectionID = "collection_id"
        case collectionName = "collection_name"
    }
}

public struct Episode: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String
    public let overview: String
    public let runtime: Int
    public let hasFile: Bool
    public let streamURL: String
    public let airDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case hasFile = "has_file"
        case streamURL = "stream_url"
        case airDate = "air_date"
    }
}

public struct Season: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let seasonNumber: Int
    public let name: String
    public let episodeCount: Int
    public let posterURL: String
    public let episodes: [Episode]

    enum CodingKeys: String, CodingKey {
        case id, name, episodes
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case posterURL = "poster_url"
    }
}

public struct TVShow: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let year: Int
    public let overview: String
    public let voteAverage: Double
    public let genres: [String]
    public let posterURL: String
    public let hasFile: Bool
    public let streamURL: String
    public let createdAt: String?
    public let tmdbID: Int?
    public let backdropURL: String?
    public let status: String?
    public let seasons: [Season]?

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, genres, seasons, status
        case voteAverage = "vote_average"
        case posterURL = "poster_url"
        case hasFile = "has_file"
        case streamURL = "stream_url"
        case createdAt = "created_at"
        case tmdbID = "tmdb_id"
        case backdropURL = "backdrop_url"
    }
}

public struct PagedItems<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let library: String?
    public let filterMode: String?

    enum CodingKeys: String, CodingKey {
        case items, total, page, library
        case pageSize = "page_size"
        case filterMode = "filter_mode"
    }
}

public struct LibraryRow: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let title: String?
    public let path: String?
    public let year: Int?
    public let publisher: String?

    public var displayTitle: String { title ?? name ?? id }
}

public struct LibraryListResponse: Codable, Sendable {
    public let items: [LibraryRow]
    public let total: Int
    public let page: Int?
    public let pageSize: Int?
    public let available: Bool?
    public let comingSoon: Bool?
    public let message: String?
    public let library: String?

    enum CodingKeys: String, CodingKey {
        case items, total, page, message, library, available
        case pageSize = "page_size"
        case comingSoon = "coming_soon"
    }
}

// MARK: - Search / discover / requests

public struct SearchResult: Codable, Identifiable, Hashable, Sendable {
    public var id: Int
    public let musicbrainzID: String?
    public let releaseGroupID: String?
    public let recordingID: String?
    public let artistName: String?
    public let albumTitle: String?
    public let title: String
    public let year: Int
    public let overview: String
    public let poster: String
    public let voteAvg: Double
    public let mediaType: String

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, poster
        case musicbrainzID = "musicbrainzId"
        case releaseGroupID = "releaseGroupId"
        case recordingID = "recordingId"
        case artistName, albumTitle, voteAvg, mediaType
    }
}

public struct DiscoverDetail: Codable, Sendable {
    public let id: Int
    public let title: String
    public let year: Int
    public let overview: String
    public let tagline: String?
    public let genres: [String]
    public let poster: String
    public let backdrop: String
    public let voteAvg: Double
    public let runtime: Int?
    public let status: String?
    public let mediaType: String
}

public struct MediaRequest: Codable, Identifiable, Sendable {
    public let id: String
    public let itemType: String
    public let itemId: String
    public let tmdbId: Int
    public let musicbrainzId: String?
    public let title: String
    public let year: Int
    public let poster: String
    public let status: String
    public let createdAt: String?
    public let updatedAt: String
}

public struct CollectionSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let movieCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case movieCount = "movie_count"
    }
}

public struct CollectionDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let movies: [Movie]
}

// MARK: - Music

public struct MusicTrack: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let albumID: String?
    public let artistID: String?
    public let title: String
    public let path: String?
    public let streamURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, path
        case albumID = "album_id"
        case artistID = "artist_id"
        case streamURL = "stream_url"
    }
}

public struct MusicAlbum: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let artistID: String?
    public let title: String
    public let year: Int?
    public let tracks: [MusicTrack]?

    enum CodingKeys: String, CodingKey {
        case id, title, year, tracks
        case artistID = "artist_id"
    }
}

public struct MusicArtistDetail: Codable, Sendable {
    public struct Artist: Codable, Sendable {
        public let id: String
        public let name: String
        public let path: String?
    }

    public let artist: Artist
    public let albums: [MusicAlbum]
}

public struct BookAuthorDetail: Codable, Sendable {
    public struct Author: Codable, Sendable {
        public let id: String
        public let name: String
        public let path: String?
    }

    public struct Book: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let year: Int?
        public let isbn: String?
    }

    public let author: Author
    public let books: [Book]
}

// MARK: - Live TV

public struct LiveTVChannel: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let number: String
    public let url: String?
    public let category: String?
}

public struct LiveTVRecording: Codable, Identifiable, Sendable {
    public let id: String
    public let channelID: String
    public let title: String
    public let start: String
    public let end: String
    public let status: String
    public let path: String?

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, status, path
        case channelID = "channel_id"
    }
}

public struct LiveTVTimer: Codable, Identifiable, Sendable {
    public let id: String
    public let channelID: String
    public let title: String
    public let start: String
    public let end: String
    public let series: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, series
        case channelID = "channel_id"
    }
}

public struct LiveTVResponse: Codable, Sendable {
    public let channels: [LiveTVChannel]
    public let recordings: [LiveTVRecording]?
    public let timers: [LiveTVTimer]?
    public let available: Bool?
}

// MARK: - Playback / auth

public struct PlaybackResolve: Codable, Sendable {
    public let streamURL: String
    public let mode: String
    public let resumeEnabled: Bool
    public let transcoderEnabled: Bool
    public let preferDirectPlay: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case streamURL = "stream_url"
        case resumeEnabled = "resume_enabled"
        case transcoderEnabled = "transcoder_enabled"
        case preferDirectPlay = "prefer_direct_play"
    }
}

public struct PlaybackSubtitleTrack: Codable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let language: String?
    public let srclang: String?
    public let src: String
    public let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, language, srclang, src
        case isDefault = "default"
    }
}

public struct QuickConnectRegisterResponse: Codable, Sendable {
    public let code: String
    public let approved: Bool
    public let pending: Bool?
    public let message: String?
}

public struct QuickConnectPollResponse: Codable, Sendable {
    public let approved: Bool
    public let code: String
    public let username: String?
    public let userID: String?
    public let sessionToken: String?

    enum CodingKeys: String, CodingKey {
        case approved, code, username
        case userID = "user_id"
        case sessionToken = "session_token"
    }
}

public struct TVLoginResponse: Codable, Sendable {
    public let sessionToken: String?
    public let userID: String?
    public let username: String?
    public let requires2FA: Bool?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case username, error
        case sessionToken = "session_token"
        case userID = "user_id"
        case requires2FA = "requires_2fa"
    }
}

// MARK: - Userdata

public enum MediaKind: String, Codable, Sendable {
    case movie, tv, episode, music, book, other
}

public struct ProgressEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: MediaKind
    public var title: String
    public var posterURL: String?
    public var href: String
    public var streamURL: String?
    public var positionSec: Double
    public var durationSec: Double
    public var updatedAt: String
    public var watched: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, href, watched
        case posterURL = "poster_url"
        case streamURL = "stream_url"
        case positionSec, durationSec, updatedAt
    }

    public init(
        id: String,
        kind: MediaKind,
        title: String,
        posterURL: String?,
        href: String,
        streamURL: String?,
        positionSec: Double,
        durationSec: Double,
        updatedAt: String,
        watched: Bool?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.posterURL = posterURL
        self.href = href
        self.streamURL = streamURL
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.updatedAt = updatedAt
        self.watched = watched
    }
}

public struct FavoriteEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: MediaKind
    public var title: String
    public var posterURL: String?
    public var href: String
    public var year: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, href, year
        case posterURL = "poster_url"
    }

    public init(id: String, kind: MediaKind, title: String, posterURL: String?, href: String, year: Int?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.posterURL = posterURL
        self.href = href
        self.year = year
    }
}

public struct QueueItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: MediaKind
    public var title: String
    public var href: String
    public var streamURL: String?
    public var posterURL: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, href
        case streamURL = "stream_url"
        case posterURL = "poster_url"
    }

    public init(id: String, kind: MediaKind, title: String, href: String, streamURL: String?, posterURL: String?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.href = href
        self.streamURL = streamURL
        self.posterURL = posterURL
    }
}

public struct Playlist: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var itemIds: [String]

    public init(id: String, name: String, itemIds: [String]) {
        self.id = id
        self.name = name
        self.itemIds = itemIds
    }
}

public struct UserPreferences: Codable, Equatable, Sendable {
    public struct DisplayPrefs: Codable, Equatable, Sendable {
        public var theme: String
        public var libraryPageSize: Int
        public var showWatchedIndicators: Bool
    }

    public struct HomePrefs: Codable, Equatable, Sendable {
        public var showContinueWatching: Bool
        public var showFavorites: Bool
        public var showRecentRequests: Bool
        public var showNextUp: Bool
    }

    public struct PlaybackPrefs: Codable, Equatable, Sendable {
        public var autoplayNext: Bool
        public var rememberPosition: Bool
        public var skipIntroSec: Int
    }

    public struct SubtitlePrefs: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var language: String
        public var textSize: String
    }

    public var display: DisplayPrefs
    public var home: HomePrefs
    public var playback: PlaybackPrefs
    public var subtitles: SubtitlePrefs
    // Retain fields owned by other clients when the BFF replaces the preferences object.
    private var rawDocument: [String: PreferenceJSON] = [:]

    public init(display: DisplayPrefs, home: HomePrefs, playback: PlaybackPrefs, subtitles: SubtitlePrefs) {
        self.display = display
        self.home = home
        self.playback = playback
        self.subtitles = subtitles
    }

    public init(from decoder: Decoder) throws {
        let raw = try [String: PreferenceJSON](from: decoder)
        let defaults = try Self.defaults.knownDocument()
        let complete = PreferenceJSON.merging(defaults, raw)
        let values = try JSONDecoder().decode(Values.self, from: JSONEncoder().encode(complete))
        self.init(display: values.display, home: values.home, playback: values.playback, subtitles: values.subtitles)
        rawDocument = raw
    }

    public func encode(to encoder: Encoder) throws { try document().encode(to: encoder) }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        (try? lhs.document()) == (try? rhs.document())
    }

    func changedPaths(from previous: Self) throws -> Set<String> {
        let before = try previous.knownDocument()
        let after = try knownDocument()
        var paths = Set<String>()
        for (section, value) in after {
            guard case let .object(fields) = value else { continue }
            let old: [String: PreferenceJSON]
            if case let .object(fields) = before[section] { old = fields } else { old = [:] }
            for (key, value) in fields where old[key] != value { paths.insert(section + "." + key) }
        }
        return paths
    }

    func applying(_ local: Self, paths: Set<String>) throws -> Self {
        var combined = try document()
        let source = try local.knownDocument()
        for path in paths {
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, case let .object(localFields) = source[parts[0]],
                  let value = localFields[parts[1]] else { continue }
            var fields: [String: PreferenceJSON] = [:]
            if case let .object(current) = combined[parts[0]] { fields = current }
            fields[parts[1]] = value
            combined[parts[0]] = .object(fields)
        }
        return try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(combined))
    }

    private struct Values: Codable {
        var display: DisplayPrefs
        var home: HomePrefs
        var playback: PlaybackPrefs
        var subtitles: SubtitlePrefs
    }

    private func knownDocument() throws -> [String: PreferenceJSON] {
        try JSONDecoder().decode([String: PreferenceJSON].self, from: JSONEncoder().encode(
            Values(display: display, home: home, playback: playback, subtitles: subtitles)
        ))
    }

    private func document() throws -> [String: PreferenceJSON] {
        try PreferenceJSON.merging(rawDocument, knownDocument())
    }

    public static let defaults = UserPreferences(
        display: .init(theme: "dark", libraryPageSize: 48, showWatchedIndicators: true),
        home: .init(showContinueWatching: true, showFavorites: true, showRecentRequests: true, showNextUp: true),
        playback: .init(autoplayNext: false, rememberPosition: true, skipIntroSec: 0),
        subtitles: .init(enabled: true, language: "eng", textSize: "md")
    )
}

private enum PreferenceJSON: Codable, Equatable, Sendable {
    case object([String: PreferenceJSON]), array([PreferenceJSON]), string(String), number(Decimal), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let array = try? value.decode([PreferenceJSON].self) { self = .array(array) }
        else { self = .object(try value.decode([String: PreferenceJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .object(object): try value.encode(object)
        case let .array(array): try value.encode(array)
        case let .string(string): try value.encode(string)
        case let .number(number): try value.encode(number)
        case let .bool(bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }

    static func merging(_ base: [String: Self], _ overlay: [String: Self]) -> [String: Self] {
        var result = base
        for (key, value) in overlay {
            if case let .object(old) = result[key], case let .object(new) = value {
                result[key] = .object(merging(old, new))
            } else { result[key] = value }
        }
        return result
    }
}

public struct UserdataBlob: Codable, Sendable {
    public var progress: [String: ProgressEntry]?
    public var favorites: [String: FavoriteEntry]?
    public var prefs: UserPreferences?
    public var playlists: [Playlist]?
    public var queue: [QueueItem]?
    public var userID: String?
    public var tenantID: String?

    enum CodingKeys: String, CodingKey {
        case progress, favorites, prefs, playlists, queue
        case userID = "user_id"
        case tenantID = "tenant_id"
    }

    public init(
        progress: [String: ProgressEntry]?,
        favorites: [String: FavoriteEntry]?,
        prefs: UserPreferences?,
        playlists: [Playlist]?,
        queue: [QueueItem]?,
        userID: String? = nil,
        tenantID: String? = nil
    ) {
        self.progress = progress
        self.favorites = favorites
        self.prefs = prefs
        self.playlists = playlists
        self.queue = queue
        self.userID = userID
        self.tenantID = tenantID
    }
}

public struct RequestTitleResponse: Codable, Sendable {
    public let requestId: String
    public let movieId: String?
    public let seriesId: String?
    public let status: String
}
