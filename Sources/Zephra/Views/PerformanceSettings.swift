import SwiftUI
import ZephraEngine

/// What the engine does with the GPU: whether it warms up, how much scratch it may hold, and
/// what it is holding right now.
struct PerformanceSettings: View {
    @AppStorage(AppSettings.warmUpOnLaunch) private var warmUpOnLaunch = AppSettings.initialWarmUpOnLaunch

    var body: some View {
        Form {
            Section {
                Toggle("Warm up the model after loading", isOn: $warmUpOnLaunch)
                Text("A throwaway generation compiles the Metal kernels, so the first real image "
                    + "is not the one that pays for it. Takes effect the next time a model loads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("GPU memory") {
                GPUMemoryRow()
                CacheLimitControl()
                WeightResidencyControl()
            }
            Section("Image decoding") {
                VAETilingControl()
            }
            Section("In use now") {
                MemoryReadout()
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Performance") {
    PerformanceSettings()
        .frame(width: 480, height: 560)
        .environment(GenerationStore.preview(state: .ready))
}
