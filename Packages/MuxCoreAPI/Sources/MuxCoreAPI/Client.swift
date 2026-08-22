import Foundation

public enum MuxCoreAPIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case httpStatus(Int, String)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .unauthorized: return "Not signed in"
        case let .httpStatus(code, detail): return "HTTP \(code): \(detail)"
        case let .decoding(err): return "Response decode failed: \(err.localizedDescription)"
        }
    }
}

public struct MuxCoreSession: Codable, Sendable {
    public let baseURL: URL
    public let sessionToken: String
    public let username: String
    public let userID: String

    public init(baseURL: URL, sessionToken: String, username: String, userID: String) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.username = username
        self.userID = userID
    }
}

public actor MuxCoreClient {
    public let session: MuxCoreSession
    private let decoder = JSONDecoder()

    public init(session: MuxCoreSession) {
        self.session = session
    }

    public static func normalizeBaseURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed) else { return nil }
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.url
    }

    // MARK: Auth (static)

    public static func registerQuickConnect(baseURL: URL) async throws -> QuickConnectRegisterResponse {
        try await postJSON(baseURL: baseURL, path: "/api/quickconnect", body: ["action": "register"], sessionToken: nil)
    }

    public static func pollQuickConnect(baseURL: URL, code: String) async throws -> QuickConnectPollResponse {
        let q = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return try await getJSON(baseURL: baseURL, path: "/api/quickconnect?code=\(q)", sessionToken: nil)
    }

    public static func loginWithPassword(baseURL: URL, username: String, password: String) async throws -> TVLoginResponse {
        try await postJSON(baseURL: baseURL, path: "/api/tv/login", body: ["username": username, "password": password], sessionToken: nil)
    }

    // MARK: Capabilities & userdata

    public func getCapabilities() async throws -> Capabilities {
        let raw: Capabilities = try await getJSON(path: "/api/capabilities")
        var caps = Capabilities.defaults
        for key in LibraryKey.allCases {
            if let v = raw.libraries[key.rawValue] { caps.libraries[key.rawValue] = v }
        }
        for key in FeatureKey.allCases {
            if let v = raw.features[key.rawValue] { caps.features[key.rawValue] = v }
        }
        return caps
    }

    public func getUserdata() async throws -> UserdataBlob {
        try await getJSON(path: "/api/userdata")
    }

    public func putUserdata(_ blob: UserdataBlob) async throws -> UserdataBlob {
        try await putJSON(path: "/api/userdata", body: blob)
    }

    // MARK: Movies & TV

    public func listMovies(page: Int = 1, pageSize: Int = 48, library: String? = nil) async throws -> PagedItems<Movie> {
        var path = "/api/movies?page=\(page)&page_size=\(pageSize)"
        if let library { path += "&library=\(library.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? library)" }
        return try await getJSON(path: path)
    }

    public func getMovie(id: String) async throws -> Movie {
        struct Wrapper: Decodable { let movie: Movie }
        let wrapped: Wrapper = try await getJSON(path: "/api/movies/\(encodePath(id))")
        return wrapped.movie
    }

    public func listTVShows(page: Int = 1, pageSize: Int = 48) async throws -> PagedItems<TVShow> {
        try await getJSON(path: "/api/tv?page=\(page)&page_size=\(pageSize)")
    }

    public func getTVShow(id: String) async throws -> TVShow {
        struct Wrapper: Decodable { let show: TVShow?; let series: TVShow?; let item: TVShow? }
        let w: Wrapper = try await getJSON(path: "/api/tv/\(encodePath(id))")
        if let show = w.show ?? w.series ?? w.item { return show }
        throw MuxCoreAPIError.decoding(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing show")))
    }

    // MARK: Optional libraries

    public func listMusic() async throws -> LibraryListResponse { try await getJSON(path: "/api/music") }
    public func listBooks() async throws -> LibraryListResponse { try await getJSON(path: "/api/books") }
    public func listComics() async throws -> LibraryListResponse { try await getJSON(path: "/api/comics") }
    public func listAudiobooks() async throws -> LibraryListResponse { try await getJSON(path: "/api/audiobooks") }
    public func getMusicArtist(id: String) async throws -> MusicArtistDetail { try await getJSON(path: "/api/music/\(encodePath(id))") }
    public func getBookAuthor(id: String) async throws -> BookAuthorDetail { try await getJSON(path: "/api/books/\(encodePath(id))") }

    // MARK: Search / discover / requests

    public func search(query: String, type: String? = nil) async throws -> [SearchResult] {
        var path = "/api/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        if let type { path += "&type=\(type)" }
        struct Wrapper: Decodable { let results: [SearchResult]? }
        let w: Wrapper = try await getJSON(path: path)
        return w.results ?? []
    }

    public func getDiscoverDetail(type: String, id: Int) async throws -> DiscoverDetail {
        try await getJSON(path: "/api/discover/\(type)/\(id)")
    }

    public func listRequests() async throws -> [MediaRequest] {
        try await getJSON(path: "/api/requests")
    }

    public func requestTitle(_ input: RequestTitleInput) async throws -> RequestTitleResponse {
        try await postJSON(path: "/api/request", body: input)
    }

    // MARK: Collections

    public func listCollections() async throws -> [CollectionSummary] {
        struct Wrapper: Decodable { let items: [CollectionSummary] }
        let w: Wrapper = try await getJSON(path: "/api/collections")
        return w.items
    }

    public func getCollection(id: String) async throws -> CollectionDetail {
        try await getJSON(path: "/api/collections/\(encodePath(id))")
    }

    // MARK: Live TV

    public func listLiveTV() async throws -> LiveTVResponse {
        try await getJSON(path: "/api/livetv")
    }

    public func createLiveTVTimer(channelID: String, title: String, series: Bool = false) async throws {
        struct Body: Encodable {
            let channel_id: String
            let title: String
            let series: Bool
        }
        struct OK: Decodable { let ok: Bool? }
        let _: OK = try await postJSON(path: "/api/livetv/timers", body: Body(channel_id: channelID, title: title, series: series))
    }

    // MARK: Playback

    public func resolvePlayback(src: String) async throws -> PlaybackResolve {
        let encoded = src.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? src
        return try await getJSON(path: "/api/playback/resolve?src=\(encoded)")
    }

    public func fetchPlaybackSubtitles(src: String) async throws -> [PlaybackSubtitleTrack] {
        let encoded = src.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? src
        struct Wrapper: Decodable { let tracks: [PlaybackSubtitleTrack] }
        let w: Wrapper = try await getJSON(path: "/api/playback/subtitles?src=\(encoded)")
        return w.tracks
    }

    nonisolated public func absoluteURL(for path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        if path.hasPrefix("/") { return URL(string: path, relativeTo: session.baseURL)?.absoluteURL }
        return URL(string: path, relativeTo: session.baseURL)?.absoluteURL
    }

    // MARK: HTTP

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        try await Self.getJSON(baseURL: session.baseURL, path: path, sessionToken: session.sessionToken, decoder: decoder)
    }

    private func postJSON<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        try await Self.postJSON(baseURL: session.baseURL, path: path, body: body, sessionToken: session.sessionToken, decoder: decoder)
    }

    private func putJSON<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        try await Self.putJSON(baseURL: session.baseURL, path: path, body: body, sessionToken: session.sessionToken, decoder: decoder)
    }

    private static func getJSON<T: Decodable>(baseURL: URL, path: String, sessionToken: String?, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw MuxCoreAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(&request, token: sessionToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw MuxCoreAPIError.decoding(error) }
    }

    private static func postJSON<T: Decodable, Body: Encodable>(baseURL: URL, path: String, body: Body, sessionToken: String?, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw MuxCoreAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        applyAuth(&request, token: sessionToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw MuxCoreAPIError.decoding(error) }
    }

    private static func putJSON<T: Decodable, Body: Encodable>(baseURL: URL, path: String, body: Body, sessionToken: String?, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw MuxCoreAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        applyAuth(&request, token: sessionToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw MuxCoreAPIError.decoding(error) }
    }

    private static func applyAuth(_ request: inout URLRequest, token: String?) {
        guard let token, !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw MuxCoreAPIError.unauthorized }
            let detail = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MuxCoreAPIError.httpStatus(http.statusCode, detail)
        }
    }

    private func encodePath(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
}

public struct RequestTitleInput: Encodable, Sendable {
    public let title: String
    public let year: Int
    public let overview: String
    public let poster: String
    public let mediaType: String
    public let tmdbId: Int?
    public let musicbrainzId: String?
    public let releaseGroupId: String?
    public let recordingId: String?
    public let artistName: String?
    public let albumTitle: String?

    public init(
        title: String,
        year: Int = 0,
        overview: String = "",
        poster: String = "",
        mediaType: String,
        tmdbId: Int? = nil,
        musicbrainzId: String? = nil,
        releaseGroupId: String? = nil,
        recordingId: String? = nil,
        artistName: String? = nil,
        albumTitle: String? = nil
    ) {
        self.title = title
        self.year = year
        self.overview = overview
        self.poster = poster
        self.mediaType = mediaType
        self.tmdbId = tmdbId
        self.musicbrainzId = musicbrainzId
        self.releaseGroupId = releaseGroupId
        self.recordingId = recordingId
        self.artistName = artistName
        self.albumTitle = albumTitle
    }
}
