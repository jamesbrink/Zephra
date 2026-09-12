import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol

/// The primary action, and the one place a refusal from the Mac is shown.
///
/// It never changes its word and it never goes away: Generate starts a picture when the Mac is
/// idle and queues one behind the running picture otherwise, exactly as on the Mac, where
/// pressing Generate mid-run adds to the queue. Stop appears *beside* it while a run is in
/// flight rather than in its place, so a second press lands on the button a thumb was already
/// reaching for instead of stopping the run it meant to queue behind.
///
/// A refusal is a sentence under the button rather than an alert. The Mac writes it — "the
/// library folder is being moved", "that model has no backend" — and an alert over a phone's
/// canvas would hide the very picture the refusal is about. With nothing refused, the same line
/// says how many runs are waiting.
struct GenerateButton: View {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft
    /// Where the last press got to, which is also where a refusal is kept.
    @State private var press = GeneratePress.idle

    var body: some View {
        let availability = GenerateAvailability(
            snapshot: client.snapshot, isLive: client.connection.isLive,
            hasPrompt: draft.settings.isReadyToGenerate)
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 10) {
                if availability.showsStop { StopRunButton() }
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!availability.isEnabled || press.isSending)
            }
            if let note = press.note ?? availability.queueNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func generate() {
        guard let snapshot = client.snapshot else { return }
        let capabilities = snapshot.model(named: draft.modelID).capabilities
        let request = draft.request(clampedBy: capabilities)
        let reference = draft.reference(allowedBy: capabilities)
        press = .sending
        Task {
            do {
                try await client.enqueue(request, reference: reference)
                press = .idle
                // Queued, so the run it becomes is one the capsule follows rather than a
                // prompt still being typed; a refused press leaves the prompt somebody's.
                draft.noteSubmitted(request)
            } catch let error as LinkError {
                press = .refused(error.reason)
            } catch {
                press = .refused("Your Mac did not answer.")
            }
        }
    }
}
