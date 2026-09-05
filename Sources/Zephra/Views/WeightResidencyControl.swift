import SwiftUI
import ZephraCore
import ZephraEngine

/// Whether a model's weights are held in memory or read from the disk on every step.
///
/// This is the setting that lets a model larger than the GPU's working set run at all, and it
/// says what that costs: a read of the whole model per step. Automatic streams only a model
/// that would otherwise page on this Mac, and only one whose family can. The choice reaches
/// the store as the picker moves; a model already loaded the other way is reloaded.
struct WeightResidencyControl: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.memoryBudget) private var budget
    @AppStorage(AppSettings.weightResidency) private var mode = AppSettings.initialWeightResidency

    var body: some View {
        Picker("Stream weights from disk", selection: $mode) {
            ForEach(WeightResidencyMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        Text(caption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .onChange(of: mode, initial: true) { apply() }
    }

    /// What streaming means for the model that is actually selected.
    private var caption: String {
        let model = store.descriptor
        guard model.streamedPeakBytes > 0 else {
            return "\(model.fullName) is always held in memory: its family cannot stream. "
                + "Automatic streams only a model that would otherwise page on this Mac."
        }
        let held = Double(model.residentBytes) / 1_000_000_000
        let streamed = Double(model.streamedPeakBytes) / 1_000_000_000
        return String(
            format: "Streaming reads %@'s %.1f GB of weights from the disk again on every step, "
                + "a few blocks at a time, so it needs about %.1f GB of GPU memory instead of "
                + "holding all of it. Slower on a Mac that could hold the model; the only way to "
                + "run it on one that cannot. Automatic streams only when this Mac would "
                + "otherwise page.",
            model.fullName, held, streamed)
    }

    private func apply() {
        store.setWeightResidencyPolicy(AppSettings.residencyPolicy(mode: mode, budget: budget))
    }
}

#Preview("Weight residency") {
    Form { Section("GPU memory") { WeightResidencyControl() } }
        .formStyle(.grouped)
        .frame(width: 480)
        .environment(GenerationStore.preview(state: .ready))
}
