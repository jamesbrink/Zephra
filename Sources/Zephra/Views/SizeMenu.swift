import SwiftUI
import ZephraCore
import ZephraEngine

/// Picks the output dimensions: the sizes this model offers, grouped by what they cost
/// against its default, the shape of the picture in the well at each of those costs, and a
/// size of one's own.
///
/// The groups are `SizeTier`'s, headed only when there is more than one, so a model whose
/// presets all cost about the same reads as a plain list; `SizeChoice` decides what each
/// holds. "Custom Size…" opens `SizeEntryPopover`; a size typed there that matches no preset
/// still shows on the button, which draws whatever is in force.
struct SizeMenu: View {
    @Environment(GenerationStore.self) private var store
    @State private var isEntering = false

    var body: some View {
        Menu {
            let grouped = SizeChoice.grouped(
                store.descriptor.capabilities, picture: store.referencePictureSize)
            ForEach(grouped, id: \.tier) { group in
                if grouped.count > 1 {
                    Section(group.tier.title) { choices(group.choices) }
                } else {
                    choices(group.choices)
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

    private func choices(_ choices: [SizeChoice]) -> some View {
        ForEach(choices, id: \.self) { choice in
            Button {
                store.settings.size = choice.size
            } label: {
                if choice.size == store.settings.size {
                    Label(choice.label, systemImage: "checkmark")
                } else {
                    Text(choice.label)
                }
            }
        }
    }
}

#Preview("Size") {
    SizeMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
