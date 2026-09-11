import SwiftUI
import ZephraLinkProtocol
import ZephraStyle

/// A run that is over: what it drew, which model drew it, when it landed, and its pictures.
///
/// The pictures come out of the cache by name — a run carries file names and nothing else, for
/// the reason `RunSummary` gives — so a run made this morning still shows its pictures on a
/// train with no signal, and one made a minute ago fills in as the thumbnails arrive.
struct FinishedRunRow: View {
    /// The run.
    let run: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ModelDot(run.modelID)
                Text(run.prompt)
                    .font(.callout)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if !run.fileNames.isEmpty {
                RunThumbnailStrip(fileNames: run.fileNames)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// When the run's last picture landed, to the minute. Today's runs only ever span today,
    /// so the time alone says it.
    private var time: String {
        guard let when = run.finishedAt ?? run.startedAt else { return "" }
        return when.formatted(date: .omitted, time: .shortened)
    }
}
