/// Which models a Mac can run at their default size, and how: exactly, tiled, or streamed.
///
/// Every entry point takes a `MemoryBudget`; the `physicalMemory:` forms are for a Mac whose
/// GPU has not been asked what it may keep, which is the tests and a build with no runtime.
extension ModelCatalog {
    /// The model to start a Mac with this budget on: the first listed variant that runs at
    /// its default size there, or `default` when none does.
    ///
    /// Without this a 16 GB Mac would open on a model its own menu marks "Needs 23 GB", load
    /// 12 GB of weights it cannot decode with, and only find the variant it can run by hand.
    public static func `default`(fitting budget: MemoryBudget) -> ModelDescriptor {
        fitting(budget: budget).first ?? zImageTurbo8bit
    }

    /// `default(fitting:)` for a Mac whose GPU has not been asked what it may keep.
    public static func `default`(fitting physicalMemory: UInt64) -> ModelDescriptor {
        `default`(fitting: MemoryBudget(physicalMemory: physicalMemory))
    }

    /// The models that run at their default size within `budget` without paging, counting
    /// the tiled VAE decode and streamed weights as available — they are what the app turns
    /// on when it matters.
    ///
    /// This is the filter behind the model picker's wording, not a gate on what can be chosen:
    /// a model left out of this list is still runnable at a smaller size.
    public static func fitting(budget: MemoryBudget) -> [ModelDescriptor] {
        all.filter { fit($0, budget: budget).runsAtDefaultSize }
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
