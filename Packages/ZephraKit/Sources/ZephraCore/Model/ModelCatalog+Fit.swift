/// Which models a Mac can run at their default size, and how: exactly, tiled, or streamed.
///
/// Every entry point takes a `MemoryBudget`; the `physicalMemory:` forms are for a Mac whose
/// GPU has not been asked what it may keep, which is the tests and a build with no runtime.
extension ModelCatalog {
    /// The model to start a Mac with this budget on: the first listed variant that runs at
    /// its default size there, and where none does, the one that comes nearest to running.
    ///
    /// Without this a 16 GB Mac would open on a model its own menu marks "Needs 23 GB", load
    /// 12 GB of weights it cannot decode with, and only find the variant it can run by hand.
    ///
    /// The second half is for a Mac smaller than any Zephra has been measured on — 8 GB, where
    /// nothing in the catalog fits. Naming the plain default there recommended the *largest*
    /// download of the six and the one wanting the most working set, which is the worst answer
    /// available; the leanest is at least the nearest thing to a run, and the picker still says
    /// what it needs rather than promising it works.
    public static func `default`(fitting budget: MemoryBudget) -> ModelDescriptor {
        if let runs = fitting(budget: budget).first { return runs }
        return leanest ?? zImageTurbo8bit
    }

    /// The catalog entry needing the least working set at its default size. Catalog order
    /// breaks a tie, since `min(by:)` keeps the first of equals.
    private static var leanest: ModelDescriptor? {
        all.min { $0.leanestPeakBytes < $1.leanestPeakBytes }
    }

    /// `default(fitting:)` for a Mac whose GPU has not been asked what it may keep.
    public static func `default`(fitting physicalMemory: UInt64) -> ModelDescriptor {
        `default`(fitting: MemoryBudget(physicalMemory: physicalMemory))
    }

    /// Every model, the ones this Mac runs at their default size first, in catalog order
    /// within each group. What a picker lists: nothing is hidden, and what is worth choosing
    /// is at the top.
    public static func ordered(for budget: MemoryBudget) -> [ModelDescriptor] {
        let runs = fitting(budget: budget)
        let ids = Set(runs.map(\.id))
        return runs + all.filter { !ids.contains($0.id) }
    }

    /// The set a Mac may choose from: the models that run at their default size within
    /// `budget` without paging, counting the tiled VAE decode and streamed weights as
    /// available — they are what the app turns on when it matters.
    ///
    /// A model left out of this list is not offered at a smaller size either. A Mac that
    /// cannot hold a model aborted the app rather than drawing something small, so the
    /// picker greys what is missing here and never loads it.
    public static func fitting(budget: MemoryBudget) -> [ModelDescriptor] {
        all.filter { fit($0, budget: budget).isSelectable }
    }

    /// `fitting(budget:)` for a Mac whose GPU has not been asked what it may keep.
    public static func fitting(physicalMemory: UInt64) -> [ModelDescriptor] {
        fitting(budget: MemoryBudget(physicalMemory: physicalMemory))
    }

    /// Where one model lands against a Mac's working-set budget: exactly, only tiled, only
    /// streamed, or not at its default size at all.
    public static func fit(_ descriptor: ModelDescriptor, budget: MemoryBudget) -> MemoryFit {
        MemoryFit(descriptor: descriptor, budget: budget)
    }

    /// `fit(_:budget:)` for a Mac whose GPU has not been asked what it may keep.
    public static func fit(_ descriptor: ModelDescriptor, physicalMemory: UInt64) -> MemoryFit {
        fit(descriptor, budget: MemoryBudget(physicalMemory: physicalMemory))
    }

    /// Whether this Mac can run the model at its default size with the exact, untiled decode.
    public static func fitsComfortably(_ descriptor: ModelDescriptor, budget: MemoryBudget) -> Bool {
        fit(descriptor, budget: budget) == .fits
    }

    /// `fitsComfortably(_:budget:)` for a Mac whose GPU has not been asked what it may keep.
    public static func fitsComfortably(
        _ descriptor: ModelDescriptor,
        physicalMemory: UInt64
    ) -> Bool {
        fitsComfortably(descriptor, budget: MemoryBudget(physicalMemory: physicalMemory))
    }
}
