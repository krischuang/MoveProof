import SwiftUI

/// Renders a piece of evidence from the App Group evidence directory.
///
/// Loading happens off the main thread and the result is cached in the view's own
/// state, so scrolling a room full of photos does not stall. A file that has gone
/// missing shows a clear placeholder rather than a blank square, because a tenant
/// needs to know their evidence is not there.
struct EvidenceThumbnail: View {

    let url: URL?
    let kind: EvidenceKind
    var size: CGFloat = 64

    @State private var image: UIImage?
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if kind == .document {
                placeholder(symbol: "doc.text.fill", tint: .accentColor)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didAttemptLoad {
                placeholder(symbol: "exclamationmark.triangle", tint: .orange)
            } else {
                placeholder(symbol: "photo", tint: .secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .task(id: url) { await loadIfNeeded() }
    }

    private func placeholder(symbol: String, tint: Color) -> some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.4))
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
        }
    }

    private func loadIfNeeded() async {
        guard kind == .photograph, let url, image == nil else { return }
        let target = size * 3
        let loaded = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: target, height: target))
                ?? UIImage(contentsOfFile: url.path)
        }.value
        image = loaded
        didAttemptLoad = true
    }
}
