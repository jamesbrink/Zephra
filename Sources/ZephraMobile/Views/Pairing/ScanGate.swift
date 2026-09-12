/// Which of the camera's readings the pairing screen acts on: each code once.
///
/// VisionKit reports a code when it first sees it and again every time the scanner is
/// restarted or the code leaves the frame and comes back, and a phone held at a Mac's screen
/// does both for as long as a pairing takes. Acting on each report was a `pair(with:)` per
/// report, and every one of them began by closing the session the one before it had open: the
/// relay saw a phone join its room and leave 260 ms later without a frame, over and over, and
/// the code never paired. So a text that is the same as the last one handed on is not handed on
/// again. A new code — a Mac that has shown another — is; the same code a second time is the
/// paste field's job.
struct ScanGate {
    /// The last text handed on, or nil before the first.
    private(set) var lastText: String?

    /// Whether this reading is new, recording it as the last one if so.
    mutating func admits(_ text: String) -> Bool {
        guard text != lastText else { return false }
        lastText = text
        return true
    }
}
