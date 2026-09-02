import SwiftUI
import ZephraEngine

/// The images along the bottom edge, newest first, including those restored from earlier
/// sessions. Invisible until there is one.
struct Filmstrip: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip
            ScrollView(.horizontal) { strip }
                .scrollIndicators(.never)
        }
        .frame(height: 80)
        .opacity(store.history.isEmpty ? 0 : 1)
        .accessibilityLabel("Images")
    }

    private var strip: some View {
        HStack(spacing: 8) {
            ForEach(store.history) { image in
                FilmstripThumbnail(image: image)
            }
        }
        .padding(2)
    }
}

#Preview("Filmstrip") {
    Filmstrip()
        .padding()
        .frame(width: 620)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}
