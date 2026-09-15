import SwiftUI
import ZephraCore
import ZephraEngine

/// Picks which model the engine runs, from what is on this Mac.
///
/// Shown only on the canvas, the same way `LibrarySortMenu` shows only in the library: the
/// model does not change what the library is listing, so a chip naming it there would be
/// something to look at rather than something to act on.
///
/// The list is the disk's, plus the chosen model whatever its state and any model whose
/// gigabytes are moving right now. Everything else the catalog knows is behind More Models…,
/// where a card can show what it makes, what it downloads and how it would run here — which is
/// a picture and three lines, not a menu row. `ModelMenuRows` is the whole of the decision and
/// is tested without a window.
///
/// Memory is still a gate. A model this Mac cannot hold at its default size, with the decode
/// tiled and the weights streamed, is greyed with the figure it wants: it aborted the app
/// rather than drawing something smaller. Choosing while an image is running is fine: the
/// running image finishes on its model, and the new one takes over for whatever is queued next.
struct ModelMenu: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(\.memoryBudget) private var budget

    var body: some View {
        if workspace.pane == .canvas {
            Menu {
                ForEach(rows) { row in
                    Button { store.switchModelFromInterface(to: row.model) } label: {
                        label(for: row)
                    }
                    .disabled(!row.isEnabled)
                    .help(row.help)
                }
                Divider()
                Button("More Models\u{2026}") { workspace.showsModelBrowser = true }
            } label: {
                // Text alone: SwiftUI flattens a toolbar menu's label to its title, so a dot
                // beside the name is drawn nowhere. The state word is part of the title and
                // survives, which is the half that had to.
                Text(labelText)
                    .font(.callout)
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .fixedSize()
            .help("Model for the next generation")
            .accessibilityLabel("Model")
        }
    }

    /// The chosen model's name, and where it stands: Loading…, Downloading, Loaded, Streaming.
    /// Nothing at all while it is simply not loaded, since the button beside it reads Load.
    private var labelText: String {
        let status = ModelLoadStatus.status(
            of: store.descriptor, state: store.state,
            loaded: store.loadedDescriptor, residency: store.loadedResidency)
        guard let word = status.word else { return store.descriptor.fullName }
        return "\(store.descriptor.fullName) \u{00B7} \(word)"
    }

    private var rows: [ModelMenuRows.Row] {
        ModelMenuRows.rows(
            budget: budget,
            availability: store.availability,
            downloading: downloading,
            chosen: store.descriptor,
            loaded: store.loadedDescriptor,
            residency: store.loadedResidency)
    }

    /// The models whose transfer is live: queued, running or paused with partial files kept.
    /// A finished or canceled one is not news and takes no row of its own.
    private var downloading: Set<ModelDescriptor.ID> {
        Set(store.downloads.items.filter {
            $0.status == .queued || $0.status == .downloading || $0.status == .paused
        }.map(\.model.id))
    }

    @ViewBuilder
    private func label(for row: ModelMenuRows.Row) -> some View {
        let title = row.note.map { "\(row.model.fullName) \u{00B7} \($0)" } ?? row.model.fullName
        if row.isChosen {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

#Preview("Model") {
    ModelMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
        .environment(WorkspaceSelection(pane: .canvas))
}
