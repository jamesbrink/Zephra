import Foundation

/// Stamping each finished check, so Settings can say when the last one ran and what it found.
extension UpdateChecker {
    /// Records a check that has just finished: on the observed `lastCheck`, for the Settings
    /// line, and in the preferences, so the next launch can still say it.
    func record(_ outcome: UpdateCheckNote.Outcome, at date: Date = .now) {
        let note = UpdateCheckNote(date: date, outcome: outcome)
        lastCheck = note
        AppSettings.recordUpdateCheck(note)
    }
}
