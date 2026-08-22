import SwiftUI

struct PosterCard: View {
    let title: String
    let subtitle: String
    let imageURL: String
    let hasFile: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Rectangle().fill(.gray.opacity(0.25))
                    }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if hasFile {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .padding(8)
                }
            }

            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
