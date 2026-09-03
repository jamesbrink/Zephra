import SwiftUI
import ZephraEngine

/// A write that failed, said once, quietly, over the capsule.
///
/// It is not a failure of the engine: the image is still on the canvas, the queue is still
/// running, and the notice goes away by itself as soon as an image saves.
struct SaveNotice: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if let failure = store.lastSaveFailure {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
                .accessibilityLabel(failure.message)
        }
    }
}
