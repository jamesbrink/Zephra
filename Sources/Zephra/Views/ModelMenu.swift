import SwiftUI
import ZephraCore
import ZephraEngine

/// Picks which model the engine runs, and says what choosing one would cost: already on disk,
/// a download away, never built, or more memory than this Mac has.
///
/// Choosing a model that has not been downloaded is allowed; the switch fetches it. Choosing
/// one that cannot be had at all, or will not fit, is not, and the row says why. Choosing while
/// an image is running is fine too: the running image finishes on its model, and the new one
/// takes over for whatever is queued next.
struct ModelMenu: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.selectedModelID) private var selectedModelID = ""

    var body: some View {
        Menu {
            ForEach(ModelCatalog.all) { model in
                Button {
                    selectedModelID = model.id
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
    /// nothing worth saying.
    private func note(for model: ModelDescriptor) -> String? {
        if let shortfall = memoryNote(model) { return shortfall }
        return store.availability[model.id]?.label
    }

    /// Why the row is disabled, phrased for a tooltip, or nil when it can be chosen.
    private func obstacle(_ model: ModelDescriptor) -> String? {
        if let shortfall = memoryNote(model) {
            return "\(model.fullName) \(shortfall.lowercased()) of memory to run."
        }
        return store.availability[model.id]?.reason
    }

    private func canChoose(_ model: ModelDescriptor) -> Bool {
        memoryNote(model) == nil && store.availability[model.id]?.isObtainable != false
    }

    /// "Needs 13 GB" for a model this Mac cannot hold, or nil when it fits.
    private func memoryNote(_ model: ModelDescriptor) -> String? {
        guard !Self.fitsThisMac.contains(model.id) else { return nil }
        let gigabytes = Int((Double(model.residentBytes) / 1_000_000_000).rounded(.up))
        return "Needs \(gigabytes) GB"
    }

    /// The models this Mac has the memory for. Physical memory does not change while the app
    /// runs, so the catalog is filtered once rather than on every row.
    private static let fitsThisMac: Set<String> = Set(
        ModelCatalog.fitting(physicalMemory: ProcessInfo.processInfo.physicalMemory).map(\.id)
    )
}

#Preview("Model") {
    ModelMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
