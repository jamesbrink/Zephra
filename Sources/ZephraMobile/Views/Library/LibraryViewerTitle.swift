import SwiftUI
import ZephraStyle

/// The strip across the top of the viewer: what is on screen, and the way out.
///
/// Its own file so the viewer holds two stored properties rather than four, and so the way
/// out is one place — the one thing in the viewer that has nothing to do with pictures.
struct LibraryViewerTitle: View {
    /// The picture on screen, or nil once the last one has been deleted.
    let entry: CachedEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.viewImagePrompt) private var showPrompt

    /// The close button's side: a fingertip, not the glyph's own size. Held here, not just in
    /// `MobileChrome`, so `ViewerChromeTests` can measure the button by the type that draws it.
    static let closeTarget = MobileChrome.viewerCloseTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(MobileChrome.viewerChromeOpacity))
                        .frame(width: Self.closeTarget, height: Self.closeTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityAction(.escape) { dismiss() }
                Spacer(minLength: 8)
                if let entry { LibraryHostLabel(entry: entry) }
            }
            if let entry {
                ViewerPromptExcerpt(text: entry.label)
                    .id(entry.id)
                if !entry.prompt.isEmpty {
                    Button { showPrompt(entry) } label: {
                        Label("View full prompt", systemImage: "text.alignleft")
                            .font(.footnote)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, MobileChrome.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.black.opacity(MobileChrome.viewerChromeOpacity))
    }
}
