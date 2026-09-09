import Testing
import ZephraCore

@testable import Zephra

@Suite("The models the chooser lists, and in what order")
struct ModelChoiceTests {
    private static func budget(gigabytes: UInt64) -> MemoryBudget {
        MemoryBudget(physicalMemory: gigabytes << 30)
    }

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
        let fitting = choices.prefix { $0.fit.runsAtDefaultSize }
        #expect(fitting.count == ModelCatalog.fitting(budget: budget).count)
        #expect(choices.dropFirst(fitting.count).allSatisfy { !$0.fit.runsAtDefaultSize })
    }

    @Test("exactly one model is the recommendation, and it is this Mac's own")
    func oneRecommendation() {
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            let budget = Self.budget(gigabytes: gigabytes)
            let choices = ModelChoice.all(for: budget)
            let recommended = choices.filter(\.isRecommended)
            #expect(recommended.count == 1)
            #expect(recommended.first?.id == ModelCatalog.default(fitting: budget).id)
        }
    }

    @Test("a 16 GB Mac is recommended klein rather than the catalog's plain default")
    func aSmallMacIsRecommendedWhatItCanRun() {
        let choices = ModelChoice.all(for: Self.budget(gigabytes: 16))
        #expect(choices.first?.isRecommended == true)
        #expect(choices.first?.id == ModelCatalog.flux2Klein4bit.id)
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
