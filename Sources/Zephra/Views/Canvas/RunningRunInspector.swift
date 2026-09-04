import SwiftUI
import ZephraCore
import ZephraEngine

/// The generation in flight, at length: how far it has got, what it was asked for, how it is
/// being made, and the way out of it.
///
/// The same shape as `FreshImageInspector` — picture, prompt, facts, action — because a run is
/// a picture that has not finished, and the column should not read as a different screen the
/// moment it does. Two facts differ: Steps says which one of how many rather than a total, and
/// Elapsed and Left replace Took.
///
/// Both of those come out of the pace `store.state` already measures, so nothing here starts a
/// clock of its own: a view's own timer would restart whenever SwiftUI rebuilt it and would
/// disagree with the subtitle. Before the first step lands there is no pace to report and the
/// two lines show a dash, which is true.
struct RunningRunInspector: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LivePreviewView(preview: store.livePreview, size: settings.size)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
                    )
                if !settings.prompt.isEmpty {
                    Text(settings.prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                facts
                Spacer(minLength: 8)
                stopButton
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            row("Model", modelName)
            row("Size", settings.size.label, style: .digits)
            row("Steps", steps, style: .digits)
            row("Seed", settings.seed.shortSeedLabel, style: .monospaced)
            row("Elapsed", elapsed, style: .digits)
            row("Left", remaining, style: .digits)
            Divider()
        }
        .font(.callout)
    }

    /// Full width, the way the inspector's other actions are: the label carries the width, not
    /// the button, or the chrome hugs the word and the one thing to do here reads as an aside.
    private var stopButton: some View {
        Button { store.cancel() } label: {
            Text(store.state == .cancelling ? "Stopping…" : "Stop")
                .frame(maxWidth: .infinity)
        }
        .disabled(store.state == .cancelling)
        .help("Stop after this step and clear the queue")
    }

    private func row(_ key: String, _ value: String, style: KeyValueStyle = .plain) -> some View {
        VStack(spacing: 0) {
            Divider()
            KeyValueRow(key, value, style: style)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
        }
    }

    /// What the run in flight was queued with, falling back to what the next one would use so
    /// the column never empties in the moment between one seed finishing and the next starting.
    private var settings: GenerationSettings { store.running?.settings ?? store.settings }

    private var modelName: String {
        (store.running?.model ?? store.descriptor).fullName
    }

    /// The step being worked on out of the run's total, or the total alone before the loop has
    /// reported: the prompt is still being read, and no step has happened yet.
    private var steps: String {
        guard let progress = store.state.denoisingProgress else { return String(settings.steps) }
        return "\(progress.step) of \(progress.total)"
    }

    /// How long the loop has been running, as the steps that have finished at the pace they
    /// took. A step is reported as it begins, so the one named is not finished yet; the text
    /// encode before them is not counted either, because it is not measured.
    private var elapsed: String {
        guard let progress = store.state.denoisingProgress, let pace = secondsPerStep else {
            return ImageFacts.unknown
        }
        let finished = max(0, progress.step - 1)
        return ImageFacts.tookLabel(seconds: Double(finished) * pace, steps: finished)
    }

    /// The engine's own countdown, never rounded down to nothing: a run with a second left has
    /// a second left, and "0 s" on a picture that has not appeared reads as a stall.
    private var remaining: String {
        guard case .generating(let event) = store.state,
              let left = event.estimatedSecondsRemaining
        else { return ImageFacts.unknown }
        return "~\(max(1, Int(left.rounded()))) s"
    }

    private var secondsPerStep: Double? {
        guard case .generating(let event) = store.state else { return nil }
        return event.secondsPerStep
    }
}

#Preview("Mid run") {
    RunningRunInspector()
        .frame(width: 320, height: 700)
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(
                phase: .denoising(step: 3, of: 4),
                fraction: 0.75,
                secondsPerStep: 8.2
            )),
            running: InterfacePreview.queuedRun(of: 1).first,
            livePreview: PreviewImages.frame()
        ))
}
