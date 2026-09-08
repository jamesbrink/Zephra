import SwiftUI

/// ⌘+ and ⌘− step the library's thumbnails through the sizes they are baked at.
///
/// The slider is continuous and these are not, deliberately: a keystroke should land on a size
/// that is already in the cache rather than somewhere between two of them, so holding ⌘+ walks
/// the whole range instantly instead of baking a fresh set at each of a dozen widths.
///
/// The largest bucket is bigger than the slider goes, so the steps are clamped to what the
/// slider can actually show — a shortcut must never put the interface somewhere the control
/// beside it cannot represent.
struct ThumbnailSizeCommands: Commands {
    @FocusedValue(\.librarySelection) private var selection

    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    /// The sizes the shortcuts land on: every bucket, clamped into the slider's range.
    private static let steps: [Double] = {
        let ceiling = AppSettings.libraryThumbnailEdgeBounds.upperBound
        var steps: [Double] = []
        for size in ThumbnailSize.allCases {
            let clamped = min(Double(size.points), ceiling)
            if steps.last != clamped { steps.append(clamped) }
        }
        return steps
    }()

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            // "Zoom In" and "Zoom Out" rather than the thumbnails' own name: ⌘+ and ⌘− are
            // named that everywhere else on the Mac, and what they do here is what they do
            // there — make what is on screen larger and smaller.
            Button("Zoom In") { edge = bigger ?? edge }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(selection == nil || bigger == nil)
            Button("Zoom Out") { edge = smaller ?? edge }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(selection == nil || smaller == nil)
            Divider()
        }
    }

    private var bigger: Double? { Self.steps.first { $0 > edge } }

    private var smaller: Double? { Self.steps.last { $0 < edge } }
}
