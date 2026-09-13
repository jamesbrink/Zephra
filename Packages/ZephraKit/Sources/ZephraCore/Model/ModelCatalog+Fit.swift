/// Which models a Mac can run at their default size, and how: exactly, tiled, or streamed.
///
/// Every entry point takes a `MemoryBudget`; the `physicalMemory:` forms are for a Mac whose
/// GPU has not been asked what it may keep, which is the tests and a build with no runtime.
extension ModelCatalog {
    /// The model to start a Mac with this budget on: the first listed variant that runs at
    /// its default size there **with its weights held in memory**, then the *leanest* that runs
    /// streamed, and where none does, the one that comes nearest to running.
    ///
    /// Without this a 16 GB Mac would open on a model its own menu marks "Needs 23 GB", load
    /// 12 GB of weights it cannot decode with, and only find the variant it can run by hand.
    ///
    /// The resident pass is why this is not simply `fitting(budget:).first`. Every family
    /// streams since the 2026-09-13 measurements, so a 16 GB Mac now *can* run Z-Image 8-bit —
    /// the first entry of `all` — by reading 6.8 GB of weights off the disk on each of nine
    /// steps. Recommending that as a first launch would hand such a Mac a 13.3 GB download and
    /// a picture that takes minutes, when klein 4-bit is two entries down, fits outright, and
    /// renders in seconds. Streaming is the lever that makes a model *possible*, not the one
    /// that makes it a good first answer; a person who wants it picks it from the chooser,
    /// where it is listed and captioned "Streams from disk".
    ///
    /// The streamed pass takes the **leanest** rather than the first in catalog order, for the
    /// same reason. Catalog order is an editorial judgement about what a Mac that can hold
    /// things should see first, and it is the wrong order once nothing is being held: on an
    /// 8 GB Mac, where every candidate streams, first-in-order is Z-Image 8-bit — a 13.3 GB
    /// download reading 6.8 GB a step — against klein 4-bit's 5.4 GB build reading 1.5 GB.
    /// Among models that are all paying the streaming tax, the one that pays least is the
    /// answer.
    ///
    /// The last fallback is for a Mac smaller than any Zephra has been measured on — 4 GB,
    /// where nothing in the catalog fits even streamed. Naming the plain default there
    /// recommended the *largest* download of the eight and the one wanting the most working
    /// set, which is the worst answer available; the leanest is at least the nearest thing to a
    /// run, and the picker still says what it needs rather than promising it works.
    public static func `default`(fitting budget: MemoryBudget) -> ModelDescriptor {
        let judged = all.map { ($0, fit($0, budget: budget)) }
        if let resident = judged.first(where: { $0.1.fitsResident })?.0 { return resident }
        let streamed = judged.filter { $0.1 == .fitsStreamed }.map(\.0)
        if let leanestStreamed = streamed.min(by: { $0.leanestPeakBytes < $1.leanestPeakBytes }) {
            return leanestStreamed
        }
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
