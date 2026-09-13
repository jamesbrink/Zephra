import SwiftUI
import ZephraCore
import ZephraEngine

/// Picks which model the engine runs, and says what choosing one would cost: already on disk,
/// a download away, never built, tiled to fit, or more memory than this Mac has.
///
/// Shown only on the canvas, the same way `LibrarySortMenu` shows only in the library: the
/// model does not change what the library is listing, so a chip naming it there would be
/// something to look at rather than something to act on.
///
/// Memory is a gate. A model this Mac cannot hold at its default size, with the decode tiled
/// and the weights streamed, is greyed with the figure it wants: it aborted the app rather than
/// drawing something smaller, so it is never chosen, never loaded and never downloaded from
/// here. A model that cannot be had at all — never built, no backend for it — is disabled for
/// its own reason. Nothing is hidden either way. Choosing while an image is running is fine
/// too: the running image finishes on its model, and the new one takes over for whatever is
/// queued next.
struct ModelMenu: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(\.memoryBudget) private var budget

    var body: some View {
        if workspace.pane == .canvas {
            Menu {
                ForEach(ModelCatalog.all) { model in
                    Button {
                        store.switchModelFromInterface(to: model)
                    } label: {
                        label(for: model)
                    }
                    .disabled(!canChoose(model))
                    .help(obstacle(model) ?? model.fullName)
                }
            } label: {
                Text(store.descriptor.fullName)
                    .font(.callout)
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .fixedSize()
            .help("Model for the next generation")
            .accessibilityLabel("Model")
        }
    }

    @ViewBuilder
    private func label(for model: ModelDescriptor) -> some View {
        let title = note(for: model).map { "\(model.fullName) · \($0)" } ?? model.fullName
        if model.id == store.descriptor.id {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// The secondary half of a row: what it would take to run this model, or nil when there is
    /// nothing worth saying. A model that cannot be had at all says so first: "Tiles the decode"
    /// beside a greyed-out row explains nothing, and a disabled menu item shows no tooltip to
    /// explain it either. What this Mac cannot hold comes next, ahead of the download size, for
    /// exactly that reason — the row is greyed by memory, so "Needs 18 GB" is what the greying
    /// means, and quoting a download that is never going to start would be the worse label. For
    /// every row that can be chosen a download still comes before the memory note.
    private func note(for model: ModelDescriptor) -> String? {
        if let status = store.downloads.status(for: model.id) { return status }
        let availability = store.availability[model.id]
        if availability?.isObtainable == false { return availability?.label }
        let fit = fit(model)
        if !fit.isSelectable { return fit.label }
        if availability?.needsNetwork == true { return availability?.label }
        if let memory = fit.label { return memory }
        return availability?.label
    }

    /// The tooltip: how this model would run here, or why it cannot be had. A model that just
    /// fits has nothing to say about memory, so the availability's own reason stands instead.
    private func obstacle(_ model: ModelDescriptor) -> String? {
        let fit = fit(model)
        guard fit != .fits else { return store.availability[model.id]?.reason }
        return fit.reason(for: model, budget: budget)
    }

    /// Two ways to be out of reach: the model cannot be obtained, or this Mac cannot hold it.
    /// `store.canSelect` is the same answer every other door reads — `switchModel` would make
    /// the pick a no-op and `startLoading` would refuse it before a byte was fetched — so the
    /// row is greyed rather than offering a press that goes nowhere.
    private func canChoose(_ model: ModelDescriptor) -> Bool {
        store.availability[model.id]?.isObtainable != false && store.canSelect(model)
    }

    /// How this model lands on this Mac. The budget is read once at launch and does not
    /// change while the app runs, and the catalog is five entries, so this is cheap enough
    /// to answer per row rather than memoise.
    private func fit(_ model: ModelDescriptor) -> MemoryFit {
        ModelCatalog.fit(model, budget: budget)
    }
}

#Preview("Model") {
    ModelMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
        .environment(WorkspaceSelection(pane: .canvas))
}
