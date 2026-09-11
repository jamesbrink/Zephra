import SwiftUI
import ZephraCore
import ZephraEngine

/// The inspector's line for a picture that started from another one: the role's own label
/// ("First frame", "Started from", "Edited from"), a small thumbnail of the source, how far the
/// generation travelled from it, and a way back to the source itself when the library still has
/// the file it came from.
///
/// The thumbnail is `ReferenceSourceThumbnail`, and the link back is `ShowSourceButton`, each
/// its own file so this row keeps to three stored properties: `facts`, `source`, and nothing
/// else it has to hold to draw either of them.
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

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 10) {
                ReferenceSourceThumbnail(source: source)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.role.inspectorRowLabel)
                        .lineLimit(1)
                    if let strengthText {
                        Text(strengthText)
                            .foregroundStyle(.secondary)
                    }
                    if let originName = facts.referenceOrigin {
                        ShowSourceButton(originName: originName)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 7)
        }
    }

    /// "Strength 0.60", or "Held exactly" for a clip whose strength held its first frame
    /// exactly (LTX-2.5's 0), or nil when there was nothing to report.
    ///
    /// Whether this is a clip is the role's own question, `.firstFrame`, and not whether
    /// `facts.length` happens to be filled in: an in-memory picture's `length` comes from
    /// `GeneratedImage.video`, which is nil for a clip whose write has not landed yet even
    /// though its role is still `.firstFrame`, and a bare "Strength 0.00" would say nothing
    /// like what actually ran.
    private var strengthText: String? {
        guard let value = facts.referenceStrengthValue else { return nil }
        if source.role == .firstFrame, value == 0 { return "Held exactly" }
        guard let strength = facts.referenceStrength else { return nil }
        return "Strength \(strength)"
    }
}

#Preview("Facts row") {
    let item = PreviewImages.library(count: 1).items[0]
    ReferenceFactsRow(facts: ImageFacts(item), source: .library(item, role: .startFrom))
        .padding(18)
        .frame(width: 320)
        .environment(ImageCache())
        .environment(LibraryIndex.preview(count: 1))
}
