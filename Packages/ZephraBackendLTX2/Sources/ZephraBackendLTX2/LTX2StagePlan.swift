import ZephraCore

/// Whether a clip is made in one stage or two.
///
/// Two stages is the reference's own route to a large frame: the eight-step ladder at half
/// the size, the latent doubled by the spatial upsampler, and three steps at the full size,
/// which is most of a one-stage run's quality for about three fifths of its step cost. It
/// needs both edges to be multiples of 64, so the half size is on the 32-pixel grid — the
/// catalog aligns every size of this family to 64 for exactly that — and a half size the
/// model still composes sensibly at: 512 pixels on the shorter edge, so a 768 x 512 default
/// runs its first stage at 384 x 256 and a 512 x 320 preset, already cheap, runs one stage.
/// `ZEPHRA_VIDEO_STAGES` forces either for one launch, for measuring.
enum LTX2StagePlan {
    /// The shortest edge, in pixels, from which two stages are worth their upsample.
    static let twoStageEdge = 512
    /// The grid the full size must be on for the half size to be on the model's.
    static let twoStageAlignment = 64

    /// Whether `width` by `height` is made in two stages.
    static func twoStage(width: Int, height: Int, environment: InferenceEnvironment) -> Bool {
        if let forced = environment.videoStages { return forced == 2 && fits(width: width, height: height) }
        return min(width, height) >= twoStageEdge && fits(width: width, height: height)
    }

    /// Whether the size can be halved onto the model's grid at all.
    static func fits(width: Int, height: Int) -> Bool {
        width % twoStageAlignment == 0 && height % twoStageAlignment == 0
    }
}
