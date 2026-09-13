import SwiftUI
import ZephraCore
import ZephraEngine

/// Whether a model's weights are held in memory or read from the disk on every step.
///
/// This is the setting that lets a model larger than the GPU's working set run at all, and it
/// says what that costs: a read of the whole model per step. Automatic streams only a model
/// that would otherwise page on this Mac, and only one whose family can. The choice reaches
/// the store as the picker moves; a model already loaded the other way is reloaded.
///
/// The budget is read off the store rather than out of the environment, where the other GPU
/// rows read theirs. Both carry the same figure — the root sets one from the other — and this
/// is the one row that hands a policy *back*: computed against the store's own budget it cannot
/// be a policy weighed on a different number from the one the store picks a fallback model by.
/// It also leaves the view at the three stored properties a view is allowed.
struct WeightResidencyControl: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.weightResidencyOverride) private var override
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
            model.fullName, held, streamed) + neverNote
    }

    /// What Never means for a model this Mac can only hold streamed: not a slower load but no
    /// load at all. The guard refuses it before the weights are read rather than letting Metal
    /// find out, and the sentence it refuses with sends the person back to this picker, so the
    /// picker says so first.
    private var neverNote: String {
        guard mode == .never,
            !ModelCatalog.fit(store.descriptor, budget: store.memoryBudget).fitsResident
        else { return "" }
        return " Never holds \(store.descriptor.fullName) in memory whatever this Mac has, "
            + "which it cannot do here: the load is refused rather than left to page."
    }

    private func apply() {
        store.setWeightResidencyPolicy(
            AppSettings.residencyPolicy(
                mode: mode, budget: store.memoryBudget, override: override))
    }
}

#Preview("Weight residency") {
    Form { Section("GPU memory") { WeightResidencyControl() } }
        .formStyle(.grouped)
        .frame(width: 480)
        .environment(GenerationStore.preview(state: .ready))
}
