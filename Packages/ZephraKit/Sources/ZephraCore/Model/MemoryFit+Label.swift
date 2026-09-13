/// The words a picker puts beside a model to say how it would run on this Mac.
///
/// These live here rather than in the view for the reason `ModelAvailability.label` does: the
/// toolbar's model menu and the first-launch chooser both answer the same question, and two
/// copies of "Streams from disk" would drift the first time one of them was reworded.
extension MemoryFit {
    /// The short line, or nil when the model just fits and there is nothing worth saying.
    public var label: String? {
        switch self {
        case .fits: nil
        case .fitsTiled: "Tiles the decode"
        case .fitsStreamed: "Streams from disk"
        case .tight(let needed): "Needs \(Self.wholeGigabytes(needed)) GB"
        }
    }

    /// The same line for a surface that must say something in every case, such as a footer
    /// describing the selection.
    public var summary: String {
        label ?? "Runs on this Mac"
    }

    /// A sentence naming the model, long enough for a tooltip or a footer: how it would run
    /// here, and for a model that does not fit, what it would take and that it is not on offer.
    ///
    /// `budget` is only read for the `tight` case, which is the one that quotes this Mac's own
    /// figure and the one that can suggest raising the wired limit.
    public func reason(for descriptor: ModelDescriptor, budget: MemoryBudget) -> String {
        let name = descriptor.fullName
        let size = "\(descriptor.capabilities.defaultSize.width) pixels"
        switch self {
        case .fits:
            return "\(name) runs at \(size) with the exact decode on this Mac."
        case .fitsTiled:
            return "\(name) decodes in tiles on this Mac, which keeps it out of swap at "
                + "\(size) for about 1 part in 255 of difference in the image."
        case .fitsStreamed:
            return "\(name) is more than this Mac's GPU can hold, so its weights are read "
                + "from the disk again on every step. It runs at \(size), slower than it "
                + "would if it were resident."
        case .tight(let needed):
            let streamed = descriptor.streamedPeakBytes > 0
                ? " and the weights streamed from disk" : ""
            let hint = MemoryFit.wouldFitWithWiredLimitRaised(descriptor, budget: budget)
                ? " Raising the GPU memory limit in Settings > Performance would let it run."
                : ""
            return "\(name) needs a GPU working set of about \(Self.wholeGigabytes(needed)) GB "
                + "at \(size), even with the decode tiled\(streamed), and this Mac's is "
                + "\(ByteCount.gigabytes(Int64(budget.gpuWorkingSet))), so it cannot be "
                + "chosen here.\(hint)"
        }
    }

    /// Gigabytes rounded up to a whole number: what a model needs is a floor, so rounding it
    /// down would name a figure that does not in fact run.
    private static func wholeGigabytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_000_000_000).rounded(.up))
    }
}
