import SwiftUI
import ZephraLinkClient

/// Which Mac this phone knows, when it came to know it, and the way to forget it.
///
/// Forgetting is behind a confirmation because it cannot be undone from here: the pairing's
/// keys are the only thing either end has, and getting them back means walking to the Mac for
/// a new code.
struct PairedMacRow: View {
    @Environment(LinkClient.self) private var client
    /// Whether the "are you sure" is up.
    @State private var isConfirming = false

    var body: some View {
        if let host = client.pairedHost {
            LabeledContent("Mac", value: host.name)
            LabeledContent("Paired", value: host.pairedAt.formatted(date: .abbreviated, time: .shortened))
            Button("Forget This Mac", role: .destructive) { isConfirming = true }
                .confirmationDialog(
                    "Forget \(host.name)?", isPresented: $isConfirming, titleVisibility: .visible
                ) {
                    Button("Forget This Mac", role: .destructive) {
                        Task { await client.forgetHost() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This phone will need a new pairing code from that Mac to connect again.")
                }
        } else {
            LabeledContent("Mac", value: "None")
        }
    }
}

#Preview("Paired Mac") {
    Form { PairedMacRow() }
        .environment(MobilePreview.client() ?? MobilePreview.unpairedClient())
}
