import Foundation

/// When Zephra last looked for a newer build, and what it found — the line under the update
/// toggle in Settings > General.
///
/// A check that finds nothing is otherwise invisible: it puts up no banner and no alert, and
/// a Mac whose checks had quietly stopped would look exactly like one that was up to date. So
/// every check that finishes is stamped, persisted through `AppSettings`, and said here.
///
/// Pure: the date and one outcome word in, the words out. The view draws the date as a
/// relative `Text`, never a formatted string, because a string is computed once and would read
/// "5 minutes ago" for the rest of the launch (the rule the Devices list follows).
struct UpdateCheckNote: Hashable, Sendable {
    /// What one check came to.
    enum Outcome: String, Hashable, Sendable {
        /// The published build is this one, or older.
        case upToDate
        /// A newer build is published.
        case found
        /// The feed could not be read.
        case failed
    }

    let date: Date
    let outcome: Outcome

    /// What the caption says before the first check has finished.
    static let notChecked = "Not checked yet."

    /// What follows "Last checked … ago".
    var tail: String {
        switch outcome {
        case .upToDate: ": up to date."
        case .found: ": a newer version is available."
        case .failed: ": the check did not finish."
        }
    }

    /// Reads a stored stamp back, or nil for a Mac that has never checked, or for anything a
    /// later build wrote that this one cannot read — nil says "not checked yet", which is
    /// better than a wrong answer.
    static func stored(seconds: Double?, outcome: String?) -> UpdateCheckNote? {
        guard let seconds, let outcome = outcome.flatMap(Outcome.init(rawValue:)) else {
            return nil
        }
        return UpdateCheckNote(date: Date(timeIntervalSince1970: seconds), outcome: outcome)
    }
}
