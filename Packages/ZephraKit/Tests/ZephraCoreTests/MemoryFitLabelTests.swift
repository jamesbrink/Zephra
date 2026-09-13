import Testing

@testable import ZephraCore

@Suite("How a picker words the way a model runs on this Mac")
struct MemoryFitLabelTests {
    private static func budget(gigabytes: UInt64) -> MemoryBudget {
        MemoryBudget(physicalMemory: gigabytes << 30)
    }

    @Test("a model that just fits has nothing to say about memory")
    func fittingSaysNothing() {
        #expect(MemoryFit.fits.label == nil)
        #expect(MemoryFit.fits.summary == "Runs on this Mac")
    }

    @Test("each lever has its own words")
    func eachLeverIsNamed() {
        #expect(MemoryFit.fitsTiled.label == "Tiles the decode")
        #expect(MemoryFit.fitsStreamed.label == "Streams from disk")
    }

    @Test("what a model needs is rounded up, since the figure is a floor")
    func neededGigabytesRoundUp() {
        // 26.07 GB of working set does not run on a Mac told "Needs 26 GB" if the figure were
        // rounded down, so the label always names a number that is in fact enough.
        #expect(MemoryFit.tight(neededBytes: 26_070_000_000).label == "Needs 27 GB")
        #expect(MemoryFit.tight(neededBytes: 26_000_000_000).label == "Needs 26 GB")
    }

    @Test("every reason names the model it is about and the size it is about")
    func reasonsNameTheirModel() {
        let budget = Self.budget(gigabytes: 16)
        for model in ModelCatalog.all {
            let reason = ModelCatalog.fit(model, budget: budget).reason(for: model, budget: budget)
            #expect(reason.contains(model.fullName))
            #expect(reason.contains("\(model.capabilities.defaultSize.width) pixels"))
        }
    }

    @Test("a model this Mac cannot hold is told so, and told which levers were counted")
    func tightSaysItCannotBeChosen() {
        // An 8 GB Mac holds nothing in the catalog, and every one of those sentences has to
        // say that the model is not on offer rather than leave a person looking for the row.
        let budget = Self.budget(gigabytes: 8)
        for model in ModelCatalog.all {
            let fit = ModelCatalog.fit(model, budget: budget)
            guard case .tight = fit else {
                Issue.record(Comment(rawValue: "\(model.id) fits an 8 GB Mac"))
                continue
            }
            let reason = fit.reason(for: model, budget: budget)
            #expect(reason.contains("so it cannot be chosen here"))
            #expect(!reason.contains("A smaller size runs"))
            #expect(
                reason.contains("even with the decode tiled and the weights streamed from disk")
                    == (model.streamedPeakBytes > 0))
        }
        // The whole sentence, in order: the levers qualify what the model needs, not what
        // this Mac has, and the figure quoted is the leanest way the family runs.
        let model = ModelCatalog.qwenImage2512_4bit
        #expect(
            ModelCatalog.fit(model, budget: budget).reason(for: model, budget: budget)
                == "\(model.fullName) needs a GPU working set of about 11 GB at "
                    + "\(model.capabilities.defaultSize.width) pixels, even with the decode "
                    + "tiled and the weights streamed from disk, and this Mac's is 6.9 GB, so "
                    + "it cannot be chosen here.")
    }

    @Test("a model that would fit with the wired limit raised is told so, and one that would not is not")
    func theWiredLimitHintIsOnlyOfferedWhenItHelps() {
        let hint = "Raising the GPU memory limit"
        // Qwen-Image's tiled peak is 26.1 GB: over a 16 GB Mac's whole RAM, so raising the
        // limit cannot help, and over a 32 GB Mac's working set but under its RAM, so it can.
        let model = ModelCatalog.qwenImage2512_4bit
        let small = Self.budget(gigabytes: 16)
        let large = Self.budget(gigabytes: 32)
        #expect(!ModelCatalog.fit(model, budget: small).reason(for: model, budget: small).contains(hint))
        let onLarge = ModelCatalog.fit(model, budget: large)
        if case .tight = onLarge {
            #expect(onLarge.reason(for: model, budget: large).contains(hint))
        }
    }
}

@Suite("The order a picker lists models in")
struct ModelCatalogOrderTests {
    @Test("every model is listed exactly once, whatever the budget")
    func nothingIsDroppedOrDoubled() {
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            let ordered = ModelCatalog.ordered(for: MemoryBudget(physicalMemory: gigabytes << 30))
            #expect(ordered.count == ModelCatalog.all.count)
            #expect(Set(ordered.map(\.id)) == Set(ModelCatalog.all.map(\.id)))
        }
    }

    @Test("the models that run at their default size come first, in catalog order")
    func fittingModelsLead() {
        let budget = MemoryBudget(physicalMemory: 16 << 30)
        let ordered = ModelCatalog.ordered(for: budget)
        let fitting = ModelCatalog.fitting(budget: budget)
        #expect(Array(ordered.prefix(fitting.count)) == fitting)
        #expect(ordered.dropFirst(fitting.count).allSatisfy {
            !ModelCatalog.fit($0, budget: budget).isSelectable
        })
    }

    @Test("a Mac nothing fits still lists everything, in catalog order")
    func aMacNothingFitsListsTheWholeCatalog() {
        let ordered = ModelCatalog.ordered(for: MemoryBudget(physicalMemory: 8 << 30))
        #expect(ordered == ModelCatalog.all)
    }
}
