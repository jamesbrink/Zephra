import Foundation
import Testing
import ZephraCore

@testable import Zephra

/// Which model a launch opens on, before any disk has been read.
@Suite("the model a launch is handed")
struct SavedModelTests {
    /// A preferences domain of its own per test, so nothing reads or writes what a person has
    /// set and two tests never see each other's answers.
    ///
    /// Handed to `body` and removed afterwards: a suite named for a UUID is one nothing will
    /// ever look at again, and left behind they accumulate in the test host's preferences, one
    /// file per run.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "io.zephra.SavedModelTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    private static func budget(gigabytes: UInt64) -> MemoryBudget {
        MemoryBudget(physicalMemory: gigabytes << 30)
    }

    /// A Mac smaller than anything the catalog has been measured on, so every entry is tight
    /// however many levers a later build gives it. Written as a budget rather than as a model
    /// that happens to be too big today: a family that learns to stream stops being too big,
    /// and a suite about refusing is not a suite about which model is largest this month.
    private static let tinyMac = budget(gigabytes: 4)

    @Test("a Mac that has never chosen opens on what it can run")
    func nothingSavedTakesTheDefault() {
        let budget = Self.budget(gigabytes: 16)
        withDefaults { store in
            #expect(
                ZephraApp.savedModel(fitting: budget, defaults: store)
                    == ModelCatalog.default(fitting: budget))
        }
    }

    @Test("a saved model this Mac can hold is the one it opens on")
    func aSelectableChoiceIsHonoured() {
        withDefaults { store in
            store.set(ModelCatalog.flux2Klein4bit.id, forKey: AppSettings.selectedModelID)
            #expect(
                ZephraApp.savedModel(fitting: Self.budget(gigabytes: 16), defaults: store)
                    == ModelCatalog.flux2Klein4bit)
        }
    }

    @Test("a saved model this Mac cannot hold steps onto what it would be started on")
    func aTightChoiceStepsOntoTheDefault() throws {
        // Opening on a model greyed in every picker would leave the window pointing at
        // something no door in the app will load.
        let budget = Self.tinyMac
        let tight = ModelCatalog.zImageTurbo8bit
        try #require(!ModelCatalog.fit(tight, budget: budget).isSelectable)
        let stepped = ModelCatalog.default(fitting: budget)
        try #require(stepped.id != tight.id, "the largest entry is never the leanest")
        try withDefaults { store in
            store.set(tight.id, forKey: AppSettings.selectedModelID)
            #expect(ZephraApp.savedModel(fitting: budget, defaults: store) == stepped)
        }
    }

    @Test("the same saved model is kept on a Mac with the memory for it")
    func theSameChoiceStandsOnABiggerMac() {
        withDefaults { store in
            store.set(ModelCatalog.zImageTurbo8bit.id, forKey: AppSettings.selectedModelID)
            #expect(
                ZephraApp.savedModel(fitting: Self.budget(gigabytes: 48), defaults: store)
                    == ModelCatalog.zImageTurbo8bit)
        }
    }

    @Test("an identifier from a build that no longer ships it is not a choice")
    func anUnknownIdentifierTakesTheDefault() {
        let budget = Self.budget(gigabytes: 48)
        withDefaults { store in
            store.set("a-model-from-another-build", forKey: AppSettings.selectedModelID)
            #expect(
                ZephraApp.savedModel(fitting: budget, defaults: store)
                    == ModelCatalog.default(fitting: budget))
        }
    }
}
