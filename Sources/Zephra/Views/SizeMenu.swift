import SwiftUI
import ZephraCore
import ZephraEngine

/// Picks the output dimensions: the sizes this model offers, grouped by what they cost
/// against its default, and a size of one's own.
///
/// The groups are `SizeTier`'s, headed only when there is more than one, so a model whose
/// presets all cost about the same reads as a plain list. "Custom Size…" opens
/// `SizeEntryPopover`; a size typed there that matches no preset still shows on the button,
/// which draws whatever is in force.
struct SizeMenu: View {
    @Environment(GenerationStore.self) private var store
    @State private var isEntering = false

    var body: some View {
        Menu {
            let capabilities = store.descriptor.capabilities
            let grouped = Self.grouped(capabilities)
            ForEach(grouped, id: \.tier) { group in
                if grouped.count > 1 {
                    Section(group.tier.title) { choices(group.sizes) }
                } else {
                    choices(group.sizes)
                }
            }
            Divider()
            Button("Custom Size…") { isEntering = true }
        } label: {
            Text(store.settings.size.label).font(.callout).monospacedDigit() + MenuChevron.text
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
        .fixedSize()
        .help("Output size")
        .accessibilityLabel("Output size")
        .popover(isPresented: $isEntering, arrowEdge: .bottom) {
            SizeEntryPopover(isPresented: $isEntering, initialText: SizeEntry.text(store.settings.size))
        }
    }

    private func choices(_ sizes: [ImageSize]) -> some View {
        ForEach(sizes, id: \.self) { size in
            Button {
                store.settings.size = size
            } label: {
                if size == store.settings.size {
                    Label(size.label, systemImage: "checkmark")
                } else {
                    Text(size.label)
                }
            }
        }
    }

    /// The presets in their listed order, gathered by tier, faster first.
    static func grouped(_ capabilities: ModelCapabilities) -> [(tier: SizeTier, sizes: [ImageSize])] {
        SizeTier.allCases.compactMap { tier in
            let sizes = capabilities.sizePresets.filter { capabilities.tier(of: $0) == tier }
            return sizes.isEmpty ? nil : (tier, sizes)
        }
    }
}

#Preview("Size") {
    SizeMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
