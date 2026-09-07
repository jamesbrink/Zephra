import SwiftUI
import ZephraEngine

/// The line under the seed field: what Return would keep, spelled as Settings spells seeds,
/// or why the text is not a seed.
///
/// Its own view so the popover keeps its three stored properties and the spelling comes from
/// the environment. Red only for text that is not empty and not a seed; an empty field is not
/// a mistake, only nothing yet.
struct SeedEntryHint: View {
    /// What has been typed so far.
    let text: String
    @Environment(\.seedFormat) private var format

    var body: some View {
        Text(hint)
            .font(.caption)
            .foregroundStyle(isValid ? .secondary : Color.red)
    }

    private var parsed: UInt64? { SeedEntry.parse(text) }

    private var isValid: Bool { text.isEmpty || parsed != nil }

    private var hint: String {
        if let parsed { return "Press Return to use \(format.label(parsed))." }
        return text.isEmpty ? "The seed as a number, or its short label." : "Not a seed."
    }
}
