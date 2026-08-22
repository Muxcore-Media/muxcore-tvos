import MuxCoreAPI
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    @State private var mode: LoginMode = .quickConnect
    @State private var username = ""
    @State private var password = ""
    @State private var quickConnectCode = ""
    @State private var statusMessage = ""
    @State private var isBusy = false
    @State private var pollTask: Task<Void, Never>?

    enum LoginMode: String, CaseIterable, Identifiable {
        case quickConnect = "Quick Connect"
        case password = "Username & Password"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.red)
                Text("MuxCore")
                    .font(.largeTitle.bold())
                Text("Sign in to your media server")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Server")
                    .font(.headline)
                TextField("https://mux.zem.systems", text: $appState.serverURLString)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Picker("Sign-in method", selection: $mode) {
                    ForEach(LoginMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: 720)

            switch mode {
            case .quickConnect:
                quickConnectPanel
            case .password:
                passwordPanel
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }
        }
        .padding(80)
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private var quickConnectPanel: some View {
        VStack(spacing: 24) {
            if quickConnectCode.isEmpty {
                Button(isBusy ? "Starting…" : "Show sign-in code") {
                    Task { await startQuickConnect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            } else {
                Text("Enter this code on the web")
                    .font(.headline)
                Text(quickConnectCode)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(8)
                Text("Open Settings → Quick Connect on mux.zem.systems while signed in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                Button("Cancel") {
                    pollTask?.cancel()
                    quickConnectCode = ""
                    statusMessage = ""
                }
            }
        }
    }

    private var passwordPanel: some View {
        VStack(spacing: 16) {
            TextField("Username", text: $username)
                .textFieldStyle(.plain)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Button(isBusy ? "Signing in…" : "Sign In") {
                Task { await signInWithPassword() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || username.isEmpty || password.isEmpty)
        }
        .frame(maxWidth: 520)
    }

    private func startQuickConnect() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let base = try appState.baseURL()
            let reg = try await MuxCoreClient.registerQuickConnect(baseURL: base)
            quickConnectCode = reg.code
            statusMessage = reg.message ?? "Waiting for approval…"
            pollTask?.cancel()
            pollTask = Task {
                await pollQuickConnect(base: base, code: reg.code)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func pollQuickConnect(base: URL, code: String) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let poll = try await MuxCoreClient.pollQuickConnect(baseURL: base, code: code)
                if poll.approved, let token = poll.sessionToken {
                    let session = MuxCoreSession(
                        baseURL: base,
                        sessionToken: token,
                        username: poll.username ?? "User",
                        userID: poll.userID ?? ""
                    )
                    appState.signIn(session: session)
                    quickConnectCode = ""
                    statusMessage = ""
                    return
                }
            } catch {
                if !Task.isCancelled {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func signInWithPassword() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let base = try appState.baseURL()
            let resp = try await MuxCoreClient.loginWithPassword(baseURL: base, username: username, password: password)
            if resp.requires2FA == true {
                statusMessage = "This account requires 2FA. Use Quick Connect from a browser session instead."
                return
            }
            guard let token = resp.sessionToken else {
                statusMessage = resp.error ?? "Sign-in failed"
                return
            }
            let session = MuxCoreSession(
                baseURL: base,
                sessionToken: token,
                username: resp.username ?? username,
                userID: resp.userID ?? ""
            )
            appState.signIn(session: session)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
