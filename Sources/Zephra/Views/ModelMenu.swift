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
/// Memory is a note, not a gate. A model whose peak is over this Mac's budget still runs at a
/// smaller size than its default, so the row says what it would take and lets it be chosen.
/// Only a model that cannot be had at all — never built, no backend for it — is disabled.
/// Choosing while an image is running is fine too: the running image finishes on its model, and
/// the new one takes over for whatever is queued next.
struct ModelMenu: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

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
    /// nothing worth saying. A model that cannot be had at all says so before anything about
    /// memory: "Tiles the decode" beside a greyed-out row explains nothing, and a disabled menu
    /// item shows no tooltip to explain it either.
    private func note(for model: ModelDescriptor) -> String? {
        let availability = store.availability[model.id]
        if availability?.isObtainable == false { return availability?.label }
        if let memory = memoryNote(model) { return memory }
        return availability?.label
    }

    /// The tooltip: how this model would run here, or why it cannot be had.
    private func obstacle(_ model: ModelDescriptor) -> String? {
        switch fit(model) {
        case .fits:
            return store.availability[model.id]?.reason
        case .fitsTiled:
            return "\(model.fullName) decodes in tiles on this Mac, which keeps it out of swap "
                + "at \(sizeText(model)) for about 1 part in 255 of difference in the image."
        case .tight(let needed):
            let gigabytes = Int((Double(needed) / 1_000_000_000).rounded(.up))
            return "\(model.fullName) needs about \(gigabytes) GB of memory at \(sizeText(model)),"
                + " even with the decode tiled, so this Mac will page there. A smaller size runs."
        }
    }

    /// Memory never disables a row: a model that pages at its default size still runs at a
    /// smaller one. Only a model that cannot be obtained at all is out of reach.
    private func canChoose(_ model: ModelDescriptor) -> Bool {
        store.availability[model.id]?.isObtainable != false
    }

    /// How this model lands on this Mac's memory, in a few words, or nil when it just fits.
    ///
    /// A tiled row is labelled even when the Automatic policy is what turns tiling on, because
    /// a menu that quietly changed how the image is decoded would be the worse of the two.
    private func memoryNote(_ model: ModelDescriptor) -> String? {
        switch fit(model) {
        case .fits: nil
        case .fitsTiled: "Tiles the decode"
        case .tight(let needed): "Needs \(Int((Double(needed) / 1_000_000_000).rounded(.up))) GB"
        }
    }

    private func sizeText(_ model: ModelDescriptor) -> String {
        "\(model.capabilities.defaultSize.width) pixels"
    }

    private func fit(_ model: ModelDescriptor) -> MemoryFit {
        Self.fitsThisMac[model.id] ?? .fits
    }

    /// How each model lands on this Mac. Physical memory does not change while the app runs,
    /// so the catalog is measured against it once rather than on every row.
    private static let fitsThisMac: [ModelDescriptor.ID: MemoryFit] = {
        let memory = ProcessInfo.processInfo.physicalMemory
        return Dictionary(
            uniqueKeysWithValues: ModelCatalog.all.map {
                ($0.id, ModelCatalog.fit($0, physicalMemory: memory))
            }
        )
    }()
}

#Preview("Model") {
    ModelMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
        .environment(WorkspaceSelection(pane: .canvas))
}
