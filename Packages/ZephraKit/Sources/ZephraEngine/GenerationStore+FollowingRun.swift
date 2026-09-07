import ZephraCore

/// Whether the canvas is watching the generation in flight, and the frames it watches it with.
///
/// `current` used to mean two things at once — the picture on the canvas, and the last thing the
/// engine made — and a finished image overwrote it whatever the user was looking at. The two are
/// separated here. Pressing Generate starts *following the run*: the canvas shows the run's own
/// frames, and the image it finishes with. Opening any other picture stops following, and from
/// then on results land in history, on the wall, and in the library without moving the canvas,
/// until the user asks to watch again.
///
/// Nothing here is persisted. Following is a property of this session's attention, and a relaunch
/// has no run to follow.
extension GenerationStore {
    /// Whether the canvas should be showing the run rather than a picture: following, and with
    /// something to follow.
    ///
    /// A run that is queued but not yet started counts, because `running` is set the moment the
    /// queue hands it over and the canvas has a size and a prompt to draw from at once.
    public var isShowingRun: Bool { followsRun && running != nil }

    /// Watches the generation in flight again, after the user had gone off to look at something
    /// else. What the running card in the sidebar does when it is clicked.
    ///
    /// The next frame lands in `livePreview` as it would have anyway, and the run's result is
    /// published to the canvas because `followsRun` is true by the time it arrives. The run's
    /// own settings and model come back into the capsule too, so the card is a run to pick up
    /// again the way a square on the wall is, and not only a picture to watch: clicking away
    /// onto an earlier picture adopted that picture's settings and model, and coming back
    /// undoes it. The run's model is the loaded one, so nothing waits for Generate; with
    /// nothing running there is nothing to restore.
    public func watchRun() {
        startFollowingRun()
        guard let running else { return }
        // The run's settings carry its own reference, or none; a library read still on its
        // way was for the settings being replaced, as in `select(_:)`.
        _ = claimReference()
        adoptForGenerate(running.model)
        settings = running.settings
    }

    /// Starts following, which is what every explicit "make me an image now" does.
    ///
    /// Only attention changes here. The frame is the run's, not the canvas's: `start(_:)` puts
    /// the previous run's last frame down when the next one begins, so it never sits on the
    /// canvas through the text encode looking like progress that had stalled, and a press of
    /// Generate that only queues behind the run in flight leaves that run's frame where it is.
    func startFollowingRun() {
        // A library picture still being read is abandoned: it was chosen before the run was,
        // and landing after the run's own result would take the canvas back off it.
        openTask?.cancel()
        openTask = nil
        followsRun = true
    }

    /// Stops following, which is what opening any other picture does. The run itself carries
    /// on, frame and all — the running card in the sidebar is still showing it, and watching
    /// again finds it there — only the canvas has looked away.
    func stopFollowingRun() { followsRun = false }

    /// Forgets the frame a run left behind, on every way a run can end. The finished image, or
    /// the absence of one, is what the canvas shows from here.
    func clearLivePreview() { livePreview = nil }
}
