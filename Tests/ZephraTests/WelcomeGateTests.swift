import Foundation
import Testing
import ZephraCore

@testable import Zephra

@MainActor
@Suite("Whether a launch opens on the first-launch model chooser")
struct WelcomeGateTests {
    /// A preferences domain of its own per test, so nothing reads or writes what a person has
    /// set and two tests never see each other's answers — and removed afterwards, since a suite
    /// named for a UUID is one nothing will ever look at again, and left behind they accumulate
    /// in the test host's preferences, one file per run.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "io.zephra.WelcomeGateTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    @Test("a Mac that has never run Zephra opens on the chooser")
    func firstLaunchShowsTheChooser() {
        withDefaults { store in
            #expect(WelcomeGate(defaults: store).isShowing)
        }
    }

    @Test("a Mac that has answered the question never sees it again")
    func answeringItOnceIsEnough() {
        withDefaults { store in
            store.set(true, forKey: AppSettings.hasChosenModel)
            #expect(!WelcomeGate(defaults: store).isShowing)
        }
    }

    @Test("a launch after an earlier one opens on the workspace, chooser flag or not")
    func anEarlierLaunchCountsAsAnAnswer() {
        // The composition root writes the selected model on every launch, first or not, so its
        // presence is what says a Zephra has run here — which is what keeps the chooser from
        // flashing in front of somebody who has been using the app since before it existed.
        withDefaults { store in
            store.set("z-image-turbo-8bit", forKey: AppSettings.selectedModelID)
            #expect(!WelcomeGate(defaults: store).isShowing)
        }
    }

    @Test("skipping the chooser is an answer, and is remembered")
    func skippingIsRemembered() {
        withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            gate.dismiss()
            #expect(!gate.isShowing)
            #expect(WelcomeGate.hasAnswered(in: store))
            #expect(!WelcomeGate(defaults: store).isShowing)
        }
    }

    private static let budget = MemoryBudget(physicalMemory: 48 << 30)

    @Test("a Mac that already has a model is not asked to choose one")
    func anAvailableModelSettlesTheChooser() {
        withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            let ready = gate.settle(
                availability: [ModelCatalog.zImageTurbo8bit.id: .available],
                budget: Self.budget,
                current: ModelCatalog.zImageTurbo8bit)
            #expect(!gate.isShowing)
            #expect(ready == ModelCatalog.zImageTurbo8bit)
        }
    }

    @Test("continuing lands on the model that is here, not on the one the store was pointing at")
    func settlingChoosesWhatIsActuallyOnDisk() {
        // A Mac with klein prefetched and nothing else: the store still holds
        // `default(fitting:)`, and continuing on that would download a second model to sit
        // beside the one already downloaded.
        withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            let ready = gate.settle(
                availability: [
                    ModelCatalog.flux2Klein4bit.id: .available,
                    ModelCatalog.zImageTurbo8bit.id: .needsDownload(bytes: 13_280_000_000),
                ],
                budget: Self.budget,
                current: ModelCatalog.zImageTurbo8bit)
            #expect(ready == ModelCatalog.flux2Klein4bit)
            #expect(!gate.isShowing)
        }
    }

    @Test("a Mac with nothing downloaded is still asked")
    func nothingOnDiskLeavesTheChooserUp() {
        withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            let ready = gate.settle(
                availability: [
                    ModelCatalog.zImageTurbo8bit.id: .needsDownload(bytes: 13_280_000_000),
                    ModelCatalog.flux2Klein4bit.id: .needsDownload(bytes: 5_360_000_000),
                ],
                budget: Self.budget,
                current: ModelCatalog.zImageTurbo8bit)
            #expect(gate.isShowing)
            #expect(ready == nil)
        }
    }

    @Test("a skip pressed while the survey was still running stays a skip")
    func settlingNeverOverrulesAnAnswerAlreadyGiven() {
        // The survey lands after the button: the chooser is already down, and answering a
        // model here would start the download the skip declined.
        withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            gate.dismiss()
            let ready = gate.settle(
                availability: [ModelCatalog.zImageTurbo8bit.id: .available],
                budget: Self.budget,
                current: ModelCatalog.zImageTurbo8bit)
            #expect(ready == nil)
            #expect(!gate.isShowing)
        }
    }

    @Test("a model that only needs building is not something to continue on")
    func onlyADownloadedModelSettlesTheChooser() {
        withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            let ready = gate.settle(
                availability: [ModelCatalog.zImageTurbo4bit.id: .needsBuild],
                budget: Self.budget,
                current: ModelCatalog.zImageTurbo8bit)
            #expect(gate.isShowing)
            #expect(ready == nil)
        }
    }

    /// A Mac smaller than anything the catalog has been measured on, so every entry is tight
    /// whatever levers a later build gives a family.
    private static let tinyMac = MemoryBudget(physicalMemory: 4 << 30)

    @Test("a downloaded model this Mac cannot hold does not settle the chooser")
    func aModelThisMacCannotHoldSettlesNothing() throws {
        // A models folder carried over from a bigger Mac: the download is finished, and the
        // model is greyed in every picker here. Continuing on it would put the chooser away and
        // open on something no door in the app will load.
        let tight = ModelCatalog.zImageTurbo8bit
        try #require(!ModelCatalog.fit(tight, budget: Self.tinyMac).isSelectable)
        try withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            let ready = gate.settle(
                availability: [tight.id: .available], budget: Self.tinyMac, current: tight)
            #expect(ready == nil)
            #expect(gate.isShowing, "the question is still worth asking")
        }
    }

    /// The leanest catalog entry and the heaviest, with a budget that holds the one and not the
    /// other — found by asking rather than named, so the pair keeps meaning what it means as
    /// families learn to stream and the measured figures move.
    private static func aBudgetBetweenTwoModels()
        -> (holdable: ModelDescriptor, tight: ModelDescriptor, budget: MemoryBudget)?
    {
        guard
            let holdable = ModelCatalog.all.min(by: { $0.leanestPeakBytes < $1.leanestPeakBytes }),
            let tight = ModelCatalog.all.max(by: { $0.leanestPeakBytes < $1.leanestPeakBytes }),
            holdable.id != tight.id
        else { return nil }
        for gigabytes in stride(from: UInt64(4), through: 128, by: 4) {
            let budget = MemoryBudget(physicalMemory: gigabytes << 30)
            if ModelCatalog.fit(holdable, budget: budget).isSelectable,
                !ModelCatalog.fit(tight, budget: budget).isSelectable
            {
                return (holdable, tight, budget)
            }
        }
        return nil
    }

    @Test("a second downloaded model this Mac can hold is what it continues on")
    func settlingSkipsPastTheOneItCannotHold() throws {
        let pair = try #require(Self.aBudgetBetweenTwoModels())
        try withDefaults { store in
            let gate = WelcomeGate(isShowing: true, defaults: store)
            let ready = gate.settle(
                availability: [pair.tight.id: .available, pair.holdable.id: .available],
                budget: pair.budget,
                current: pair.tight)
            #expect(ready == pair.holdable)
            #expect(!gate.isShowing)
        }
    }
}
