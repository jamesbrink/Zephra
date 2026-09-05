import SwiftUI
import ZephraEngine

/// How many seeds one press of Generate queues, in the capsule where the queue chip used to
/// be. The chip counted what was already waiting; this decides what happens next, which is the
/// more useful thing to have under your hand — the queue itself is now in the sidebar.
struct BatchCountControl: View {
    @AppStorage(AppSettings.batchCount) private var count = AppSettings.initialBatchCount

    /// The counts worth offering: powers of two up to the engine's own limit, so raising the
    /// limit adds a row here and nothing else has to be remembered. A slider or a stepper for
    /// four choices would be more control than there is to exercise.
    private static let options: [Int] = {
        var counts = [1]
        while let last = counts.last, last * 2 <= GenerationStore.batchLimit {
            counts.append(last * 2)
        }
        return counts
    }()

    var body: some View {
        Menu {
            ForEach(Self.options, id: \.self) { option in
                Button {
                    count = option
                } label: {
                    if option == count {
                        Label("\(option)", systemImage: "checkmark")
                    } else {
                        Text("\(option)")
                    }
                }
            }
        } label: {
            // The number says what it counts: a bare "4" beside a glyph was a puzzle.
            Label(count == 1 ? "1 seed" : "\(count) seeds", systemImage: "square.stack")
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .buttonStyle(.accessoryBar)
        .monospacedDigit()
        .fixedSize()
        .help("Queue this many seeds each time you press Generate.")
        .accessibilityLabel("Seeds per run")
    }
}

#Preview("Batch") {
    BatchCountControl()
        .padding()
}
