import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol

/// The primary action, and the one place a refusal from the Mac is shown.
///
/// It never changes its word: Generate starts a picture when the Mac is idle and queues one
/// behind the running picture otherwise, exactly as on the Mac. While the Mac is rendering it
/// is replaced by Stop, since that is the only thing worth pressing then.
///
/// A refusal is a sentence under the button rather than an alert. The Mac writes it — "the
/// library folder is being moved", "that model has no backend" — and an alert over a phone's
/// canvas would hide the very picture the refusal is about.
struct GenerateButton: View {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft
    /// What the Mac last said no to, or nil.
    @State private var refusal: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isGenerating {
                Button("Stop", role: .destructive) { stop() }
                    .buttonStyle(.bordered)
            } else {
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerate)
            }
            if let refusal {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Whether the Mac is rendering something right now.
    private var isGenerating: Bool {
        client.snapshot?.engine.kind == .generating
    }

    /// The three things a press needs: a live session, a Mac that will take work, and a prompt.
    private var canGenerate: Bool {
        client.connection.isLive && client.snapshot?.acceptsWork == true
            && draft.settings.isReadyToGenerate
    }

    private func generate() {
        guard let snapshot = client.snapshot else { return }
        let capabilities = snapshot.model(named: draft.modelID).capabilities
        let request = draft.request(clampedBy: capabilities)
        let reference = draft.reference(allowedBy: capabilities)
        refusal = nil
        Task {
            do {
                try await client.enqueue(request, reference: reference)
            } catch let error as LinkError {
                refusal = error.reason
            } catch {
                refusal = "Your Mac did not answer."
            }
        }
    }

    private func stop() {
        Task { try? await client.cancel() }
    }
}
