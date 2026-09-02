import SwiftUI

/// What the engine does once the weights are in memory. Read on the way into `bootstrap()`,
/// so a change here takes effect the next time the model is loaded.
struct PerformanceSettings: View {
    @AppStorage(AppSettings.warmUpOnLaunch) private var warmUpOnLaunch = AppSettings.initialWarmUpOnLaunch

    var body: some View {
        Form {
            Toggle("Warm up the model after loading", isOn: $warmUpOnLaunch)
            Text("A throwaway generation compiles the Metal kernels, so the first real image "
                + "is not the one that pays for it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

#Preview("Performance") {
    PerformanceSettings()
        .frame(width: 480, height: 300)
}
