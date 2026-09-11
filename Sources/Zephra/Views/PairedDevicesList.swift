import SwiftUI
import ZephraLinkHost

/// The phones this Mac has agreed to talk to, and the one thing that can be done to them.
///
/// Revoking is immediate and needs no confirmation: the phone is told why, its session closes,
/// and pairing again is showing a code — which is a smaller thing to undo than a dialog is to
/// read. What a person cannot do here is rename a device: the name is the phone's own, and a
/// list where the names were editable would be a list nobody could match to a phone in a drawer.
struct PairedDevicesList: View {
    @Environment(CompanionHost.self) private var host: CompanionHost?

    var body: some View {
        if let host, !host.devices.isEmpty {
            ForEach(host.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(Self.seen(device.lastSeen))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke") { Task { await host.revoke(device) } }
                }
            }
        } else {
            Text("No iPhone is paired with this Mac.")
                .foregroundStyle(.secondary)
        }
    }

    /// When the phone was last here, in the words a list wants.
    private static func seen(_ date: Date?) -> String {
        guard let date else { return "Never connected" }
        return "Last seen \(date.formatted(.relative(presentation: .named)))"
    }
}

#Preview("Devices") {
    Form { PairedDevicesList() }
        .formStyle(.grouped)
        .frame(width: 520)
}
