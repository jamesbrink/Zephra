import Testing
import ZephraCore

@testable import Zephra

@Suite("The models the chooser lists, and in what order")
struct ModelChoiceTests {
    private static func budget(gigabytes: UInt64) -> MemoryBudget {
        MemoryBudget(physicalMemory: gigabytes << 30)
    }

    /// A Mac smaller than anything the catalog has been measured on, so every entry is tight
    /// whatever levers a later build gives a family. Written as a budget rather than as a model
    /// that happens to be too big today: a family that learns to stream stops being too big,
    /// and a suite about greying is not a suite about which entry is largest this month.
    private static let tinyMac = budget(gigabytes: 4)

    @Test("every model is listed, whether or not this Mac can run it")
    func nothingIsHidden() {
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            let choices = ModelChoice.all(for: Self.budget(gigabytes: gigabytes))
            #expect(choices.count == ModelCatalog.all.count)
            #expect(Set(choices.map(\.id)) == Set(ModelCatalog.all.map(\.id)))
        }
    }

    @Test("the models that run at their default size here come first")
    func fittingModelsLead() {
        let budget = Self.budget(gigabytes: 16)
        let choices = ModelChoice.all(for: budget)
        let fitting = choices.prefix { $0.fit.isSelectable }
        #expect(fitting.count == ModelCatalog.fitting(budget: budget).count)
        #expect(choices.dropFirst(fitting.count).allSatisfy { !$0.fit.isSelectable })
    }

    @Test("at most one model is the recommendation, and it is this Mac's own")
    func oneRecommendation() {
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            let budget = Self.budget(gigabytes: gigabytes)
            let choices = ModelChoice.all(for: budget)
            let recommended = choices.filter(\.isRecommended)
            #expect(recommended.count <= 1)
            if let one = recommended.first {
                #expect(one.id == ModelCatalog.default(fitting: budget).id)
                #expect(one.isSelectable)
            }
        }
    }

    @Test("tight models are listed greyed, with the figure they want")
    func tightModelsAreListedGreyed() {
        let choices = ModelChoice.all(for: Self.tinyMac)
        let tight = choices.filter { !$0.isSelectable }
        #expect(!tight.isEmpty, "nothing measured runs on a Mac this small")
        for choice in tight {
            // Listed, and never recommended or pressable; the note says what it would take.
            #expect(!choice.isRecommended)
            #expect(choice.fit.label?.hasPrefix("Needs ") == true)
            #expect(choice.reason.contains("cannot be chosen here"))
        }
    }

    @Test("a Mac too small for the whole catalog is recommended nothing")
    func aTinyMacIsRecommendedNothing() {
        let choices = ModelChoice.all(for: Self.tinyMac)
        #expect(choices.allSatisfy { !$0.isSelectable })
        #expect(choices.allSatisfy { !$0.isRecommended })
        // Still every card, so the catalog reads the same on every Mac.
        #expect(choices.count == ModelCatalog.all.count)
    }

    @Test("a 16 GB Mac is recommended klein rather than the catalog's plain default")
    func aSmallMacIsRecommendedWhatItCanRun() {
        // The recommendation rather than the first card: which entries lead the list is catalog
        // order among the ones that fit, and a family that learns to stream joins that group.
        let choices = ModelChoice.all(for: Self.budget(gigabytes: 16))
        #expect(choices.first(where: \.isRecommended)?.id == ModelCatalog.flux2Klein4bit.id)
    }

    @Test("each model's reason names it and is answered against the same budget as its fit")
    func reasonsAreAboutTheirOwnModel() {
        let budget = Self.budget(gigabytes: 16)
        for choice in ModelChoice.all(for: budget) {
            #expect(choice.reason.contains(choice.model.fullName))
            #expect(choice.reason == choice.fit.reason(for: choice.model, budget: budget))
        }
    }
}
