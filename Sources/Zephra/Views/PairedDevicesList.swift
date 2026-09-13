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
                        Self.caption(
                            DeviceStatus.of(
                                connected: host.isConnected(device), lastSeen: device.lastSeen)
                        )
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

    /// The line under the name. A relative `Text` rather than a formatted string, because the
    /// string was computed once when the row was drawn and nothing ever drew it again: a phone
    /// read "last seen 8 minutes ago" for the rest of the launch. SwiftUI keeps the relative
    /// style ticking on its own, and `isConnected` is observed, so a session opening or closing
    /// redraws the row.
    private static func caption(_ status: DeviceStatus) -> Text {
        switch status {
        case .connected: Text("Connected")
        case .seen(let date): Text("Last seen ") + Text(date, style: .relative) + Text(" ago")
        case .never: Text("Never connected")
        }
    }
}

#Preview("Devices") {
    Form { PairedDevicesList() }
        .formStyle(.grouped)
        .frame(width: 520)
}
