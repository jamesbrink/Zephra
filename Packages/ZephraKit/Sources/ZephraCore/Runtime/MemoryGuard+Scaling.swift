/// The two figures a refusal is worked out from: what a model peaks at the way it is being
/// loaded, and what one request costs on top of the weights.
extension MemoryGuard {
    /// The measured peak for this way of loading the model: the streamed figure when the
    /// weights are read from disk every step, and otherwise the tiled peak when the decode is
    /// tiled and the exact one when it is not. A family with no streamed figure is charged its
    /// resident peak whatever the residency says, since it will be loaded resident regardless.
    func peakBytes(
        of descriptor: ModelDescriptor, residency: WeightResidency, tile: Int?
    ) -> Int64 {
        if residency == .streamed, descriptor.streamedPeakBytes > 0 {
            return descriptor.streamedPeakBytes
        }
        return tile == nil ? descriptor.peakBytes : descriptor.tiledPeakBytes
    }

    /// What the run itself needs on top of what is held: the peak less the weights, scaled by
    /// pixels times frames against the size the peak was measured at.
    ///
    /// What is held is the allocator's own reading where it has one, since that is the truth
    /// about this load — streamed, tiled, whatever the person chose — and the descriptor's
    /// resident figure only where nothing has been allocated yet.
    ///
    /// A streamed load holds nothing the descriptor names. `residentBytes` is what the weights
    /// weigh *held*, and for every streaming family that is larger than the streamed peak
    /// itself — Z-Image 8-bit holds 12.2 GB resident and peaks at 6.4 GB streamed — so
    /// subtracting it would floor the transient at zero and charge a streamed run nothing at
    /// all, which is the refusal this guard exists to make. A streamed load with no allocator
    /// reading is therefore charged its whole peak; once the weights are in there is a
    /// reading, and that is the truth about this load.
    ///
    /// The scaling is linear, which is honest at the default size and optimistic a long way
    /// from it; `ROADMAP.md` carries that until a second size is measured per family.
    func transientBytes(
        of descriptor: ModelDescriptor,
        residency: WeightResidency,
        tile: Int?,
        settings: GenerationSettings,
        runtime: MemorySnapshot
    ) -> Int64 {
        let peak = peakBytes(of: descriptor, residency: residency, tile: tile)
        let held: Int64 =
            if runtime.activeBytes > 0 {
                Int64(runtime.activeBytes)
            } else if residency == .streamed, descriptor.streamedPeakBytes > 0 {
                0
            } else {
                descriptor.residentBytes
            }
        let transient = max(0, peak - held)
        return Int64((Double(transient) * requestScale(of: descriptor, settings: settings)).rounded())
    }

    /// How much bigger this request is than the one the family's peak was measured at: pixels
    /// times frames, both ends, with a frame count of at least one so a picture model's
    /// arithmetic is the same as a clip model's.
    private func requestScale(
        of descriptor: ModelDescriptor, settings: GenerationSettings
    ) -> Double {
        let capabilities = descriptor.capabilities
        let measured =
            Double(capabilities.defaultSize.pixelCount) * Double(max(1, capabilities.defaultFrames))
        guard measured > 0 else { return 1 }
        let asked = Double(settings.size.pixelCount) * Double(max(1, settings.frames))
        return asked / measured
    }
}
