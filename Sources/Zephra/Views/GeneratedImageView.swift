import AppKit
import SwiftUI

/// The picture itself, letterboxed into whatever space the canvas has.
///
/// This is the one orchestrated motion in the app: a finished image fades up over 250 ms.
/// Give the view the image's identity so a new picture gets a new view, and a new fade.
struct GeneratedImageView: View {
    /// Pixels already decoded by `ImageCache`; nothing is decoded inside `body`.
    let bitmap: NSImage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        Image(nsImage: bitmap)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    isVisible = true
                }
            }
            .accessibilityLabel("Generated image")
    }
}

#Preview("Finished image") {
    GeneratedImageView(bitmap: NSImage(data: PreviewImages.sample().pngData) ?? NSImage())
        .padding(40)
        .frame(width: 520, height: 520)
        .background(Color.canvasBackground)
}
