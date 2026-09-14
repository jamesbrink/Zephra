/// The step down to streaming: the one place a residency is decided against what the Mac has
/// free rather than against the budget alone.
extension MemoryGuard {
    /// How `descriptor`'s weights should be loaded right now, and why they cannot be, or nil
    /// when they can.
    ///
    /// `WeightResidencyPolicy` answers from the budget, which does not move: under `automatic`
    /// a model that fits the working set held whole is resident, and that is the right answer
    /// for the menu's note and the Performance tab, which are about what this Mac could do.
    /// It is the wrong answer at a load, where the question is what this Mac has free — on
    /// 2026-09-13 klein 4-bit fitted a 12124 MiB working set resident, 11.2 GB was free, and
    /// the load was refused outright although its 4.06 GB streamed peak would have fitted
    /// several times over.
    ///
    /// So: ask the policy, check that answer against the machine, and where a resident load
    /// under `automatic` is short, check streaming before refusing. Only `automatic` steps
    /// down — `never` is a choice to hold the weights and `always` is already streaming — and
    /// only a family that has a measured streamed peak can be stepped down to. A refusal after
    /// the step-down quotes the streamed figure, which is both the smaller number and the
    /// honest one: it is what the load that was actually going to be attempted would have
    /// taken.
    public func loadResidency(
        for descriptor: ModelDescriptor,
        policy: WeightResidencyPolicy,
        tile: Int?,
        machine: MachineMemory?,
        runtime: MemorySnapshot
    ) -> (residency: WeightResidency, shortfall: MemoryShortfall?) {
        let asked = policy.residency(for: descriptor)
        let shortfall = loadShortfall(
            for: descriptor, residency: asked, mode: policy.mode, tile: tile, machine: machine,
            runtime: runtime)
        guard shortfall != nil, policy.mode == .automatic, asked == .resident,
            descriptor.streamedPeakBytes > 0
        else { return (asked, shortfall) }
        return (
            .streamed,
            loadShortfall(
                for: descriptor, residency: .streamed, mode: policy.mode, tile: tile,
                machine: machine, runtime: runtime)
        )
    }
}
