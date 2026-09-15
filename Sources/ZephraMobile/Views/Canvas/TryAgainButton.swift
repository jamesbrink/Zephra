import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol

/// The way back from a Mac whose run was lost, in one press.
///
/// A GPU fault leaves the Mac in `.failed` with its weights still in memory, and until this
/// button existed a phone had no way out of it: picking the same model again is a no-op the Mac
/// still answers `.ok` to, so the phone saw success over nothing happening. `Command.loadModel`
/// is a command of its own for exactly that reason, and it names the model the failure was
/// about rather than whatever the draft has since been moved to.
///
/// Hidden against a Mac that does not understand the command. There Generate alone is the way
/// back, which the Mac's own widened admission already makes work.
///
/// A refusal is the Mac's own sentence under the button, the way a refused press of Generate is
/// answered, never an alert: this is a button somebody may press twice in ten seconds, and a
/// sheet each time would be in the way of the second press.
struct TryAgainButton: View {
    @Environment(LinkClient.self) private var client
    /// Where one press has got to.
    @State private var press: GeneratePress = .idle

    var body: some View {
        if Self.isShown(supportsModelLoading: client.supportsModelLoading, kind: engine?.kind) {
            VStack(spacing: 6) {
                Button("Try Again") { retry() }
                    .buttonStyle(.borderedProminent)
                    .disabled(press.isSending)
                if let note = press.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Whether the button is on screen at all: only against a Mac that takes the command, and
    /// only while there is a failure to come back from.
    static func isShown(supportsModelLoading: Bool, kind: EngineStateDTO.Kind?) -> Bool {
        supportsModelLoading && kind == .failed
    }

    /// Where the Mac's engine is, which is what the button is about.
    private var engine: EngineStateDTO? { client.snapshot?.engine }

    /// Reads the failed run's model in again, and says so if the Mac refuses.
    private func retry() {
        guard let modelID = engine?.modelID else { return }
        press = .sending
        Task {
            do {
                try await client.loadModel(modelID)
                press = .idle
            } catch {
                press = .refused((error as? LinkError)?.reason ?? error.localizedDescription)
            }
        }
    }
}
