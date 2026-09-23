import Foundation

/// The update check's own record: when it last finished and what it found.
extension AppSettings {
    /// When the last update check finished, as seconds since 1970. Unset until one has.
    static let lastUpdateCheck = "lastUpdateCheck"
    /// What that check found, as an `UpdateCheckNote.Outcome` raw value.
    static let lastUpdateOutcome = "lastUpdateOutcome"

    /// The last check, or nil for a Mac that has never finished one.
    static func lastUpdateCheckNote() -> UpdateCheckNote? {
        UpdateCheckNote.stored(
            seconds: store.object(forKey: lastUpdateCheck) as? Double,
            outcome: store.string(forKey: lastUpdateOutcome))
    }

    /// Records a check that has just finished.
    static func recordUpdateCheck(_ note: UpdateCheckNote) {
        write(note.date.timeIntervalSince1970, to: lastUpdateCheck)
        write(note.outcome.rawValue, to: lastUpdateOutcome)
    }
}
