import SwiftUI
import ZephraEngine

/// "Queue a variation": the same request again, with a fresh seed.
///
/// Disabled for an imported picture, which carries no request to repeat, and while the engine
/// cannot take work — a queue drained during a download or a load would swap models under
/// whatever is already running.
struct QueueVariationButton: View {
    /// The image to make another of.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button { store.queueVariation(of: item) } label: {
            Text("Queue a variation").frame(maxWidth: .infinity)
        }
        .disabled(!canQueue)
    }

    /// The same test `queueVariation(of:)` makes before it does anything, said in public terms:
    /// a running generation is the one case where the engine is busy and will still take more.
    private var canQueue: Bool {
        guard let record = item.provenance.record,
              record.settings().isReadyToGenerate
        else { return false }
        return store.state.acceptsGeneration || store.running != nil
    }
}
