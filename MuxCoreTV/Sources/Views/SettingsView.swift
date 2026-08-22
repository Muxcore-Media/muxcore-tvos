import MuxCoreAPI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userdata: UserdataStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let session = appState.session {
                        LabeledContent("Signed in as", value: session.username)
                        LabeledContent("Server", value: session.baseURL.absoluteString)
                    }
                    Button("Sign Out", role: .destructive) { appState.signOut() }
                }

                Section("Home") {
                    Toggle("Continue watching", isOn: boolBinding { $0.home.showContinueWatching })
                    Toggle("Favorites", isOn: boolBinding { $0.home.showFavorites })
                    Toggle("Next up", isOn: boolBinding { $0.home.showNextUp })
                    Toggle("Recent requests", isOn: boolBinding { $0.home.showRecentRequests })
                }

                Section("Playback") {
                    Toggle("Remember position", isOn: boolBinding { $0.playback.rememberPosition })
                    Toggle("Autoplay next episode", isOn: boolBinding { $0.playback.autoplayNext })
                }

                Section("Subtitles") {
                    Toggle("Enabled", isOn: boolBinding { $0.subtitles.enabled })
                }

                Section("Display") {
                    Toggle("Watched indicators", isOn: boolBinding { $0.display.showWatchedIndicators })
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
