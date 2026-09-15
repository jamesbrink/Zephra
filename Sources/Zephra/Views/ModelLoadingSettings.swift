import SwiftUI
import ZephraCore

/// When a model's weights are read in, and when they go back.
///
/// Off by default, which is the change this section exists to state: choosing a model is
/// choosing it, and Load or a press of Generate is what asks for the gigabytes. Turning it on
/// is the old behaviour — the launch loads what was chosen last time, and a pick in the menu
/// swaps the weights behind it.
struct ModelLoadingSettings: View {
    @AppStorage(AppSettings.loadModelsAutomatically)
    private var loadAutomatically = AppSettings.initialLoadModelsAutomatically
    @AppStorage(AppSettings.idleUnloadMinutes)
    private var idleMinutes = AppSettings.initialIdleUnloadMinutes

    var body: some View {
        Section("Loading") {
            Toggle("Load models automatically", isOn: $loadAutomatically)
            Text("On, the launch loads the model chosen last time and picking another swaps "
                + "the weights. Off, Load or a press of Generate is what reads them in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Unload after idle", selection: $idleMinutes) {
                ForEach(IdleUnloadDelay.allCases, id: \.rawValue) { delay in
                    Text(Self.title(of: delay)).tag(delay.rawValue)
                }
            }
        }
    }

    /// How long a wait reads on a picker. Minutes up to the hour, which is where a person
    /// stops counting in them.
    private static func title(of delay: IdleUnloadDelay) -> String {
        switch delay {
        case .never: "Never"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .thirtyMinutes: "After 30 minutes"
        case .oneHour: "After 1 hour"
        }
    }
}

#Preview("Loading") {
    Form { ModelLoadingSettings() }
        .formStyle(.grouped)
        .frame(width: 520, height: 220)
}
