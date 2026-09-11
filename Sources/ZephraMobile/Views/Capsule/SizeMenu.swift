import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// Picks the size of what the Mac makes next: the model's own presets, grouped by what they
/// cost against its default, the shape of the picture in the well at each of those costs, and
/// a size of one's own.
///
/// `SizeOptions` decides what the menu holds; this only draws it. The groups are headed only
/// where there is more than one, so a model whose presets all cost about the same reads as a
/// plain list, exactly as the Mac's menu does.
struct SizeMenu: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft
    /// Whether the sheet for typing a size is up.
    @State private var isEntering = false

    var body: some View {
        let grouped = SizeOptions.grouped(
            capabilities: capabilities.capabilities, reference: draft.referenceSize)
        Menu {
            ForEach(grouped, id: \.tier) { group in
                if grouped.count > 1 {
                    Section(group.tier.title) { rows(group.choices) }
                } else {
                    rows(group.choices)
                }
            }
            Divider()
            Button("Custom Size…") { isEntering = true }
        } label: {
            Text(draft.settings.size.label).font(.callout).monospacedDigit()
        }
        .accessibilityLabel("Output size")
        .sheet(isPresented: $isEntering) {
            SizeEntrySheet(capabilities: capabilities)
        }
    }

    private func rows(_ choices: [SizeChoice]) -> some View {
        ForEach(choices, id: \.self) { choice in
            Button {
                draft.settings.size = choice.size
            } label: {
                if choice.size == draft.settings.size {
                    Label(choice.label, systemImage: "checkmark")
                } else {
                    Text(choice.label)
                }
            }
        }
    }
}
