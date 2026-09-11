import SwiftUI
import ZephraLinkHost

/// Whether an iPhone may reach this Mac, the code that lets one in, and the ones already let in.
///
/// Two switches, deliberately apart. The first opens a port on the local network and puts the
/// Mac on Bonjour; the second lets a phone somewhere else meet it on a relay, which is a
/// different thing to agree to and does not follow from the first. Both are off until asked for.
struct CompanionSettings: View {
    @AppStorage(AppSettings.companionEnabled) private var isEnabled = AppSettings.initialCompanionEnabled
    @AppStorage(AppSettings.companionRelayEnabled) private var usesRelay = AppSettings.initialCompanionRelayEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Allow Zephra for iPhone to connect", isOn: $isEnabled)
                Toggle("Allow access outside home network", isOn: $usesRelay)
                    .disabled(!isEnabled)
                CompanionNameField()
            } footer: {
                Text("Your pictures and prompts stay on this Mac. A phone sees what this Mac shows it, and only while it is paired.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pair a device") {
                PairingQRView()
            }
            Section("Devices") {
                PairedDevicesList()
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Companion") {
    CompanionSettings()
        .frame(width: 520, height: 600)
}
