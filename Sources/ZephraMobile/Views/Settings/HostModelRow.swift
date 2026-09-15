import SwiftUI
import ZephraLinkProtocol

/// One of a Mac's models, with what that Mac will do about it on request.
///
/// A Mac that understands the two loading commands is asked to load or to give the weights back,
/// which is what its own Load and Unload do; an older Mac keeps the one button there has always
/// been, `switchModel`, which on that Mac both chooses and loads. Unload appears only on the row
/// whose weights are in, and only while the engine is not in the middle of something.
struct HostModelRow: View {
    let host: HostConnection
    let model: ModelSummary
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(model.label, value: host.client.snapshot?.availability[model.id]?.label ?? "Unknown")
            if let marker = ModelLoadWord.marker(for: model.id, engine: engine) {
                Text(marker).font(.caption).foregroundStyle(.secondary)
            }
            if host.client.supportsModelLoading {
                Button("Load on \(host.name)") { ask { try await host.client.loadModel(model.id) } }
                    .disabled(!host.client.connection.isLive)
                if engine?.loadedModelID == model.id {
                    Button("Unload") { ask { try await host.client.unloadModel() } }
                        .disabled(!host.client.connection.isLive || engine?.isBusy == true)
                }
            } else {
                Button("Load on \(host.name)") { ask { try await host.client.switchModel(model.id) } }
                    .disabled(!host.client.connection.isLive)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityHint("May download or prepare this model. Auto never starts a download.")
    }

    /// Where the Mac's engine is, which is what says whether anything is loaded here.
    private var engine: EngineStateDTO? { host.client.snapshot?.engine }

    /// Asks the Mac, and keeps its sentence where the buttons are rather than in an alert.
    private func ask(_ work: @escaping () async throws -> Void) {
        failure = nil
        Task {
            do { try await work() } catch { failure = error.localizedDescription }
        }
    }
}
