import AppKit
import SwiftUI
import ZephraEngine

/// The inspector's line for a picture that started from another one: the role's own label
/// ("First frame", "Started from", "Edited from"), a small thumbnail of the source, how far the
/// generation travelled from it, and a way back to the source itself when the library still has
/// the file it came from.
///
/// The thumbnail is never read on the main actor. `LibraryItem.referenceImage` is a synchronous
/// whole-file read, so a library source runs it inside a detached task started from
/// `.task(id:)`; a picture the session still holds in memory already has its bytes at hand and
/// only needs the decode, which `ImageCache.referenceThumbnail` does off the main actor either
/// way.
struct ReferenceFactsRow: View {
    /// Where the source picture's bytes come from, and the role it plays for the model that
    /// made this image — computed at the call site from that model's own capabilities, since a
    /// record's model need not be the one currently chosen.
    enum Source: Hashable {
        case library(LibraryItem, role: ReferenceRole)
        case bytes(Data, role: ReferenceRole)

        var role: ReferenceRole {
            switch self {
            case .library(_, let role): role
            case .bytes(_, let role): role
            }
        }
    }

    /// The formatted facts, for the strength and the origin file name.
    let facts: ImageFacts
    /// The source picture and the role it played.
    let source: Source

    @Environment(ImageCache.self) private var cache
    @Environment(LibraryIndex.self) private var index
    @Environment(\.viewLibraryItem) private var viewLibraryItem
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 10) {
                thumbnailView
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.role.inspectorRowLabel)
                        .lineLimit(1)
                    if let strengthText {
                        Text(strengthText)
                            .foregroundStyle(.secondary)
                    }
                    if let originItem {
                        Button("Show Source") { viewLibraryItem(originItem) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 7)
        }
        .task(id: source) { await loadThumbnail() }
    }

    private var thumbnailView: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius, style: .continuous)
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(
                            RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius, style: .continuous)
                        )
                }
            }
    }

    /// "Strength 0.60", or "Held exactly" for a clip whose strength held its first frame
    /// exactly (LTX-2.5's 0), or nil when there was nothing to report.
    private var strengthText: String? {
        guard let value = facts.referenceStrengthValue else { return nil }
        if facts.length != nil, value == 0 { return "Held exactly" }
        guard let strength = facts.referenceStrength else { return nil }
        return "Strength \(strength)"
    }

    /// The library item the picture came out of, when the library still has it. Recently
    /// Deleted is excluded by `LibraryIndex.item(named:)` itself.
    private var originItem: LibraryItem? {
        facts.referenceOrigin.flatMap(index.item(named:))
    }

    /// Puts the old picture down first and checks for cancellation after every await: the
    /// selection can move while a read is in flight, `.task(id:)` cancels this task but not
    /// the detached read or the decode it awaits, and a slow source landing after a quick one
    /// would put the wrong picture beside the new selection's facts.
    private func loadThumbnail() async {
        thumbnail = nil
        let png: Data?
        switch source {
        case .library(let item, _):
            png = await Task.detached(priority: .userInitiated) { item.referenceImage }.value
        case .bytes(let data, _):
            png = data
        }
        guard !Task.isCancelled, let png else { return }
        let made = await cache.referenceThumbnail(png)
        guard !Task.isCancelled else { return }
        thumbnail = made
    }
}
