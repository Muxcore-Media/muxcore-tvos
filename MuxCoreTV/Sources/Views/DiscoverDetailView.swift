import MuxCoreAPI
import SwiftUI

struct DiscoverDetailView: View {
    @EnvironmentObject private var appState: AppState
    let type: String
    let tmdbID: Int

    @State private var detail: DiscoverDetail?
    @State private var message: String?

    var body: some View {
        Group {
            if let detail {
                VStack(alignment: .leading, spacing: 20) {
                    Text(detail.title).font(.largeTitle.bold())
                    Text("\(detail.year) · \(detail.mediaType.uppercased())").foregroundStyle(.secondary)
                    Text(detail.overview).font(.title3).foregroundStyle(.secondary)
                    Button("Request title") { Task { await request(detail) } }
                        .buttonStyle(.borderedProminent)
                }.padding(72)
            } else {
                ProgressView("Loading…")
            }
        }
        .task { await load() }
        .alert("Discover", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func load() async {
        guard let client = appState.client else { return }
        detail = try? await client.getDiscoverDetail(type: type, id: tmdbID)
    }

    private func request(_ detail: DiscoverDetail) async {
        guard let client = appState.client else { return }
        do {
            _ = try await client.requestTitle(RequestTitleInput(
                title: detail.title,
                year: detail.year,
                overview: detail.overview,
                poster: detail.poster,
                mediaType: detail.mediaType,
                tmdbId: detail.id
            ))
            message = "Requested \(detail.title)"
        } catch {
            message = error.localizedDescription
        }
    }
}
