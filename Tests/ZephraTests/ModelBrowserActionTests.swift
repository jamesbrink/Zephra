import Testing
import ZephraCore

@testable import Zephra

/// The one button under the model browser's cards: what it says, and whether it may be pressed.
@Suite("the model browser's footer")
struct ModelBrowserActionTests {
    @Test("offers the download and its size for a model that is not on this Mac")
    func offersDownload() {
        let action = ModelBrowserAction.action(
            availability: .needsDownload(bytes: 5_400_000_000), fit: .fits,
            isChosen: false, isLoaded: false)
        #expect(action == .download(bytes: 5_400_000_000))
        #expect(action.label == "Download 5.4 GB")
        #expect(action.isEnabled)
        // The footer turns into the transfer's own row, so the sheet stays up around it.
        #expect(!action.dismisses)
    }

    @Test("offers the download for a model that is packed after it is fetched")
    func offersDownloadForABuild() {
        #expect(
            ModelBrowserAction.action(
                availability: .needsDownloadAndBuild(bytes: 7_000_000_000), fit: .fitsTiled,
                isChosen: true, isLoaded: false) == .download(bytes: 7_000_000_000))
    }

    @Test("offers Build for a release that is here and a variant that is not")
    func offersBuild() {
        let action = ModelBrowserAction.action(
            availability: .needsBuild, fit: .fits, isChosen: false, isLoaded: false)
        #expect(action == .build)
        #expect(action.label == "Build Model")
    }

    @Test("offers Use for a model already here that is not the one chosen")
    func offersUse() {
        let action = ModelBrowserAction.action(
            availability: .available, fit: .fitsStreamed, isChosen: false, isLoaded: false)
        #expect(action == .use)
        #expect(action.label == "Use Model")
        #expect(action.dismisses)
    }

    @Test("offers Load for the chosen model that is here and not in memory")
    func offersLoad() {
        let action = ModelBrowserAction.action(
            availability: .available, fit: .fits, isChosen: true, isLoaded: false)
        #expect(action == .load)
        #expect(action.label == "Load Model")
        #expect(action.dismisses)
    }

    @Test("offers only Done for the model that is chosen and loaded")
    func offersDone() {
        #expect(
            ModelBrowserAction.action(
                availability: .available, fit: .fits, isChosen: true, isLoaded: true) == .done)
    }

    @Test("greys a model this Mac cannot hold, and names the gigabytes it needs")
    func greysWhatCannotBeHeld() {
        let action = ModelBrowserAction.action(
            availability: .available, fit: .tight(neededBytes: 18_000_000_000),
            isChosen: false, isLoaded: false)
        #expect(action == .unavailable("Needs 18 GB"))
        #expect(!action.isEnabled)
        #expect(!action.dismisses)
    }

    @Test("greys a model that cannot be got at all, and memory is asked first")
    func greysWhatCannotBeHad() {
        #expect(
            ModelBrowserAction.action(
                availability: .missing(reason: "never built"), fit: .fits,
                isChosen: false, isLoaded: false) == .unavailable("Isn't Available"))
        // Memory before the disk: a model this Mac cannot hold says so even when it is missing.
        #expect(
            ModelBrowserAction.action(
                availability: .missing(reason: "never built"),
                fit: .tight(neededBytes: 18_000_000_000),
                isChosen: false, isLoaded: false) == .unavailable("Needs 18 GB"))
    }
}
