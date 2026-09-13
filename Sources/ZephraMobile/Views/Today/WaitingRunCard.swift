import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraStyle

/// A run still waiting its turn: what it will draw, how many and how big, and a cross that
/// takes the whole run back out of the queue.
///
/// The whole run, not one seed of it. A run is what was asked for, so it is what can be taken
/// back — the Mac's `WaitingRunCard` makes the same argument, and removing four seeds one at a
/// time was never a thing anybody wanted to do. The seeds are found by their batch, which is
/// the run's identity.
struct WaitingRunCard: View {
    /// The run that is waiting.
    let run: RunSummary

    @Environment(LinkClient.self) private var client
    @Environment(\.dynamicTypeSize) private var typeSize

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        layout {
            ModelDot(run.modelID)
            Text(run.prompt)
                .font(.callout)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(detail)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button { cancel() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .disabled(!client.connection.isLive)
            .accessibilityLabel("Remove from queue")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
        )
    }

    /// The size, and the count before it when there is more than one seed to make.
    private var detail: String {
        let size = "\(run.width)\u{00D7}\(run.height)"
        return run.seedCount > 1 ? "\(run.seedCount) seeds \u{00B7} \(size)" : size
    }

    /// Takes every seed of this run out of the queue.
    private func cancel() {
        let waiting = (client.snapshot?.queue ?? []).filter { $0.batchID == run.id }
        Task {
            for entry in waiting {
                _ = try? await client.request(.removeFromQueue(entry.id))
            }
        }
    }
}
