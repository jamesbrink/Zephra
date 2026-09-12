import SwiftUI

/// The wait between two attempts at the Mac, counted down, with the way to skip it.
///
/// The countdown is `Text(timerInterval:)`, which is the system's own: it is one view that
/// redraws itself from the clock, not a timer of ours ticking a piece of state. That matters
/// here for the reason the whole app runs still — a repeating animation over a streamed step
/// took a 16 GB M4 mini's GPU down, and `make lint-layers` fails on one.
///
/// Retry Now is offered because the wait is a guess. Thirty seconds is right for a Mac that
/// has gone to sleep and wrong for one somebody has just woken up, and the person looking at
/// this row is usually the person who woke it.
struct ReconnectingRow: View {
    /// When the next attempt is due.
    let until: Date

    @Environment(LinkReconnect.self) private var reconnect: LinkReconnect?

    var body: some View {
        HStack {
            Text("Reconnecting in \(Text(timerInterval: Self.countdown(to: until), countsDown: true))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            if let reconnect {
                Button("Retry Now") { reconnect.retryNow() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }

    /// The span the countdown runs over, which is never a backwards one.
    ///
    /// A deadline can be in the past by the time this draws: the attempt it was waiting for is
    /// under way, or the phone was asleep through the whole wait. `Date()...until` would then
    /// be a range whose upper bound is below its lower, and that is a trap and not a shrug —
    /// the app would stop at a countdown, which is the least deserving place to stop at.
    static func countdown(to until: Date, from now: Date = Date()) -> ClosedRange<Date> {
        now...max(until, now)
    }
}

#Preview("Reconnecting") {
    Form { ReconnectingRow(until: Date().addingTimeInterval(8)) }
}
