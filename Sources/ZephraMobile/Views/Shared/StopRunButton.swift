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
            Task { try? await client.cancel() }
        } label: {
            Image(systemName: "stop.circle.fill")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!client.connection.isLive)
        .accessibilityLabel("Stop Generating")
    }
}
