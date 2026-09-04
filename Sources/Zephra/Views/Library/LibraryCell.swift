import SwiftUI
import ZephraEngine

/// One image in the grid: the picture, a star if it is a favourite, a badge if it was made
/// larger from another, and what a press means.
///
/// Two taps rather than one, and the two-tap gesture is declared first, which is the whole
/// trick: SwiftUI offers a tap to the gestures in the order they were attached, so a
/// single-tap handler written first would swallow the first half of every double-click.
///
/// The modifiers a click was made with come from `NSEvent` at the moment of the press, because
/// SwiftUI's gestures do not carry them on macOS. The cell does not interpret them — it says
/// what was held and lets the grid, which knows what is on screen, work out what that means.
struct LibraryCell: View {
    /// The image this cell shows.
    let item: LibraryItem
    /// What to do about a plain press, with whatever was held down while it happened.
    let onPress: (LibraryCursor.ClickModifiers) -> Void

    @Environment(\.viewLibraryItem) private var viewLibraryItem

    var body: some View {
        LibraryThumbnail(item: item)
            .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) { favourite }
            .overlay(alignment: .topLeading) { upscaled }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { viewLibraryItem(item) }
            .onTapGesture(count: 1) { onPress(.current) }
            .draggable(item)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var favourite: some View {
        if item.isFavourite {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(ZephraChrome.shadowOpacity), radius: 3, y: 1)
                .padding(6)
        }
    }

    @ViewBuilder
    private var upscaled: some View {
        if let upscale = item.upscale {
            UpscaleBadge(factor: upscale.factor)
        }
    }

    /// What VoiceOver reads: the prompt, which is the only thing about an image worth saying
    /// out loud, and the file's name for an import that has not got one.
    private var label: String {
        item.prompt.isEmpty ? item.fileName : item.prompt
    }
}

#Preview("Cell") {
    let items = PreviewImages.library(count: 4).items
    return HStack(spacing: 12) {
        ForEach(items) { item in
            LibraryCell(item: item) { _ in }
                .frame(width: 168, height: 168)
        }
    }
    .padding(24)
    .environment(\.libraryThumbnails, LibraryThumbnails(cache: ThumbnailCache(), edge: 168))
}
