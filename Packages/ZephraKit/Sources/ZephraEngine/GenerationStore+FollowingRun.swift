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
    /// Setting the flag is the whole of it: the next frame lands in `livePreview` as it would
    /// have anyway, and the run's result is published to the canvas because `followsRun` is true
    /// by the time it arrives.
    public func watchRun() { followsRun = true }

    /// Starts following, which is what every explicit "make me an image now" does.
    func startFollowingRun() {
        followsRun = true
        // The previous run's last frame is not this run's first: it would sit on the canvas
        // through the text encode and the first steps, looking like progress that had stalled.
        livePreview = nil
    }

    /// Stops following and drops the frame with it, which is what opening any other picture
    /// does. The run itself carries on; only the canvas has looked away.
    func stopFollowingRun() {
        followsRun = false
        livePreview = nil
    }

    /// Forgets the frame a run left behind, on every way a run can end. The finished image, or
    /// the absence of one, is what the canvas shows from here.
    func clearLivePreview() { livePreview = nil }
}
