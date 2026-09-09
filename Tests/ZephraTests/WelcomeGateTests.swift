import Foundation
import Testing
import ZephraCore

@testable import Zephra

@MainActor
@Suite("Whether a launch opens on the first-launch model chooser")
struct WelcomeGateTests {
    /// A preferences domain of its own per test, so nothing reads or writes what a person has
    /// set and two tests never see each other's answers.
    private func defaults(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: "io.zephra.WelcomeGateTests.\(name)")!
    }

    @Test("a Mac that has never run Zephra opens on the chooser")
    func firstLaunchShowsTheChooser() {
        #expect(WelcomeGate(defaults: defaults()).isShowing)
    }

    @Test("a Mac that has answered the question never sees it again")
    func answeringItOnceIsEnough() {
        let store = defaults()
        store.set(true, forKey: AppSettings.hasChosenModel)
        #expect(!WelcomeGate(defaults: store).isShowing)
    }

    @Test("a launch after an earlier one opens on the workspace, chooser flag or not")
    func anEarlierLaunchCountsAsAnAnswer() {
        // The composition root writes the selected model on every launch, first or not, so its
        // presence is what says a Zephra has run here — which is what keeps the chooser from
        // flashing in front of somebody who has been using the app since before it existed.
        let store = defaults()
        store.set("z-image-turbo-8bit", forKey: AppSettings.selectedModelID)
        #expect(!WelcomeGate(defaults: store).isShowing)
    }

    @Test("skipping the chooser is an answer, and is remembered")
    func skippingIsRemembered() {
        let store = defaults()
        let gate = WelcomeGate(isShowing: true, defaults: store)
        gate.dismiss()
        #expect(!gate.isShowing)
        #expect(WelcomeGate.hasAnswered(in: store))
        #expect(!WelcomeGate(defaults: store).isShowing)
    }

    private static let budget = MemoryBudget(physicalMemory: 48 << 30)

    @Test("a Mac that already has a model is not asked to choose one")
    func anAvailableModelSettlesTheChooser() {
        let gate = WelcomeGate(isShowing: true, defaults: defaults())
        let ready = gate.settle(
            availability: [ModelCatalog.zImageTurbo8bit.id: .available],
            budget: Self.budget,
            current: ModelCatalog.zImageTurbo8bit)
        #expect(!gate.isShowing)
        #expect(ready == ModelCatalog.zImageTurbo8bit)
    }

    @Test("continuing lands on the model that is here, not on the one the store was pointing at")
    func settlingChoosesWhatIsActuallyOnDisk() {
        // A Mac with klein prefetched and nothing else: the store still holds
        // `default(fitting:)`, and continuing on that would download a second model to sit
        // beside the one already downloaded.
        let gate = WelcomeGate(isShowing: true, defaults: defaults())
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

    @Test("a Mac with nothing downloaded is still asked")
    func nothingOnDiskLeavesTheChooserUp() {
        let gate = WelcomeGate(isShowing: true, defaults: defaults())
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

    @Test("a skip pressed while the survey was still running stays a skip")
    func settlingNeverOverrulesAnAnswerAlreadyGiven() {
        // The survey lands after the button: the chooser is already down, and answering a
        // model here would start the download the skip declined.
        let gate = WelcomeGate(isShowing: true, defaults: defaults())
        gate.dismiss()
        let ready = gate.settle(
            availability: [ModelCatalog.zImageTurbo8bit.id: .available],
            budget: Self.budget,
            current: ModelCatalog.zImageTurbo8bit)
        #expect(ready == nil)
        #expect(!gate.isShowing)
    }

    @Test("a model that only needs building is not something to continue on")
    func onlyADownloadedModelSettlesTheChooser() {
        let gate = WelcomeGate(isShowing: true, defaults: defaults())
        let ready = gate.settle(
            availability: [ModelCatalog.zImageTurbo4bit.id: .needsBuild],
            budget: Self.budget,
            current: ModelCatalog.zImageTurbo8bit)
        #expect(gate.isShowing)
        #expect(ready == nil)
    }

    @Test("the canvas can ask for the chooser back")
    func reopening() {
        let gate = WelcomeGate(isShowing: false, defaults: defaults())
        gate.reopen()
        #expect(gate.isShowing)
    }
}
