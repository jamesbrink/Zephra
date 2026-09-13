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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            layout {
                ModelDot(run.modelID)
                Text(run.prompt)
                    .font(.callout)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
                    .fixedSize()
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
