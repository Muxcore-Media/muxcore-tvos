import MuxCoreAPI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let session = appState.session {
                        LabeledContent("Signed in as", value: session.username)
                        LabeledContent("Server", value: session.baseURL.absoluteString)
                    }
                    Button("Sign Out", role: .destructive) { appState.signOut() }
                }

                Section("Home") {
                    Toggle("Continue watching", isOn: boolBinding(\.home.showContinueWatching))
                    Toggle("Favorites", isOn: boolBinding(\.home.showFavorites))
                    Toggle("Next up", isOn: boolBinding(\.home.showNextUp))
                    Toggle("Recent requests", isOn: boolBinding(\.home.showRecentRequests))
                }

                Section("Playback") {
                    Toggle("Remember position", isOn: boolBinding(\.playback.rememberPosition))
                    Toggle("Autoplay next episode", isOn: boolBinding(\.playback.autoplayNext))
                }

                Section("Subtitles") {
                    Toggle("Enabled", isOn: boolBinding(\.subtitles.enabled))
                }

                Section("Display") {
                    Toggle("Watched indicators", isOn: boolBinding(\.display.showWatchedIndicators))
                }

                Section("About") {
                    LabeledContent("App", value: "MuxCore TV")
                    LabeledContent("Version", value: "0.2.0")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<UserPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { userdata.prefs[keyPath: keyPath] },
            set: { value in userdata.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}
