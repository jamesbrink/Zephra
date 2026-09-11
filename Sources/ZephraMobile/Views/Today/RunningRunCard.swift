import SwiftUI
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraStyle

/// The run being rendered right now, in safelight amber.
///
/// Amber means the model is working, here as on the Mac, and it is the only amber on the phone
/// for the same reason. The step count, the pace and the phase all come off `EngineStateDTO`,
/// which the Mac derives — the phone never works out whether a run is busy or finishing, since
/// that is a rule the Mac already knows and two copies of a rule can disagree.
///
/// The bar is a plain `ProgressView` and it does not animate on its own: a phone in somebody's
/// hand redrawing sixty times a second while a Mac's GPU is flat out is two devices working.
struct RunningRunCard: View {
    /// The run in flight.
    let run: RunSummary

    @Environment(LinkClient.self) private var client

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ModelDot(run.modelID)
                Text(run.prompt)
                    .font(.callout)
                    .lineLimit(2)
                Spacer(minLength: 8)
                StopRunButton()
            }
            ProgressView(value: engine?.fraction ?? 0)
                .tint(.safelight)
            Text(detail)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZephraChrome.warningWash,
            in: RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
                .strokeBorder(ZephraChrome.warningStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating: \(run.prompt)")
    }

    /// Where the engine is, which is what every number in the card comes off.
    private var engine: EngineStateDTO? { client.snapshot?.engine }

    /// "Step 4 of 9 · 0.7 s a step", or the phase alone where there are no steps to count —
    /// decoding a clip, encoding it, loading the weights.
    private var detail: String {
        guard let engine else { return "Working" }
        var parts: [String] = []
        if let step = engine.step, let steps = engine.steps, !engine.isFinishing {
            parts.append("Step \(step) of \(steps)")
        } else if let phase = engine.phase {
            parts.append(phase)
        }
        if let pace = engine.secondsPerStep {
            parts.append("\(DurationLabel.text(seconds: pace, fraction: true)) a step")
        }
        if run.seedCount > 1 { parts.append("\(run.seedCount) seeds") }
        return parts.isEmpty ? "Working" : parts.joined(separator: " \u{00B7} ")
    }
}

/// Stop, which is the one thing a phone may do to a run in flight.
///
/// Its own view so the card holds two stored properties rather than three, and because Stop is
/// the one control here that is a command rather than a reading.
private struct StopRunButton: View {
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
