import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The two facts a first model is chosen on: what it transfers, and how it runs here.
///
/// The size comes from `store.availability`, which already answers what is actually missing
/// rather than what the release weighs — a variant published ready-made on the mirror
/// transfers its packed size, a third of the release's, and a Mac that already has half of it
/// is charged for the rest. Before the survey lands the catalog's own figure stands in by the
/// same rule, so a card is never blank and never quotes a number the download will contradict.
struct ModelChoiceFacts: View {
    @Environment(GenerationStore.self) private var store

    /// The model and its fit.
    let choice: ModelChoice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(transfer)
                .monospacedDigit()
            Spacer(minLength: 4)
            Text(choice.fit.summary)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// What choosing this model transfers, in the words `ModelAvailability` already uses.
    private var transfer: String {
        store.availability[choice.model.id]?.label ?? estimate
    }

    /// The catalog's own figure, for the frame or two before the disk has been read: the
    /// packed size for a variant the mirror publishes ready-made, the release otherwise.
    private var estimate: String {
        let model = choice.model
        let bytes = model.isPublishedPrebuilt ? model.builtBytes : model.transferBytes
        return "\(ByteCount.gigabytes(bytes)) download"
    }
}

#Preview("Facts") {
    VStack(alignment: .leading, spacing: 10) {
        ForEach(ModelChoice.all(for: MemoryBudget(physicalMemory: 16 << 30))) {
            ModelChoiceFacts(choice: $0)
        }
    }
    .frame(width: 280)
    .padding(24)
    .background(Color.canvasBackground)
    .environment(GenerationStore.preview(state: .idle))
}
