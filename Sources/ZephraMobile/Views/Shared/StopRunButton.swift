import SwiftUI
import ZephraLinkClient

/// Stop, which is the one thing a phone may do to a run in flight.
///
/// In `Views/Shared/` because two surfaces draw it the same way: the Today tab's running card,
/// and the capsule, where it sits beside Generate rather than in place of it — a Mac rendering
/// a picture takes another behind it, so the press that queues one must stay where a thumb
/// expects it.
struct StopRunButton: View {
    @Environment(LinkClient.self) private var client

    var body: some View {
        Button {
            let run = client.snapshot?.running?.id
            Task {
                if client.supportsMultiHost, let run { try? await client.cancelRun(run) }
                else { try? await client.cancel() }
            }
        } label: {
            Label(client.supportsMultiHost ? "Stop Run" : "Stop All on Mac", systemImage: "stop.circle.fill")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!client.connection.isLive)
        .accessibilityLabel(client.supportsMultiHost ? "Stop Run on \(client.snapshot?.hostName ?? "Mac")" : "Stop All Work on \(client.snapshot?.hostName ?? "Mac")")
    }
}
