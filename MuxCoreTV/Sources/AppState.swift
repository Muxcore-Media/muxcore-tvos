import Foundation
import MuxCoreAPI

@MainActor
final class AppState: ObservableObject {
    @Published var session: MuxCoreSession?
    @Published var client: MuxCoreClient?
    @Published var capabilities: Capabilities = .defaults
    @Published var capsLoading = false
    @Published var serverURLString: String = UserDefaults.standard.string(forKey: "muxcore.serverURL") ?? "https://mux.zem.systems"

    let userdata = UserdataStore()

    private let sessionKey = "muxcore.session"

    init() {
        restoreSession()
    }

    var isSignedIn: Bool { session != nil }

    func restoreSession() {
        guard
            let data = UserDefaults.standard.data(forKey: sessionKey),
            let saved = try? JSONDecoder().decode(MuxCoreSession.self, from: data)
        else { return }
        applySession(saved)
    }

    func signIn(session newSession: MuxCoreSession) {
        UserDefaults.standard.set(serverURLString, forKey: "muxcore.serverURL")
        if let data = try? JSONEncoder().encode(newSession) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
        applySession(newSession)
    }

    func signOut() {
        session = nil
        client = nil
        capabilities = .defaults
        userdata.bind(client: nil)
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    func baseURL() throws -> URL {
        guard let url = MuxCoreClient.normalizeBaseURL(serverURLString) else {
            throw MuxCoreAPIError.invalidURL
        }
        return url
    }

    func refreshCapabilities() async {
        guard let client else { return }
        capsLoading = true
        defer { capsLoading = false }
        if let caps = try? await client.getCapabilities() {
            capabilities = caps
        }
    }

    private func applySession(_ saved: MuxCoreSession) {
        session = saved
        client = MuxCoreClient(session: saved)
        userdata.bind(client: client)
        Task {
            await refreshCapabilities()
            await userdata.pullFromServer()
        }
    }
}
