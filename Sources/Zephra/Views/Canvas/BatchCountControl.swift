import SwiftUI

/// How many seeds one press of Generate queues, in the capsule where the queue chip used to
/// be. The chip counted what was already waiting; this decides what happens next, which is the
/// more useful thing to have under your hand — the queue itself is now in the sidebar.
struct BatchCountControl: View {
    @AppStorage(AppSettings.batchCount) private var count = AppSettings.initialBatchCount

    /// The counts worth offering. Doubling reaches the limit in four steps, and a slider or a
    /// stepper for four choices would be more control than there is to exercise.
    private static let options = [1, 2, 4, 8]

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
            Label("\(count)", systemImage: "square.stack")
        }
        .menuStyle(.button)
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
