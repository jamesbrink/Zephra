import AppKit
import Testing
import ZephraCore

@testable import Zephra

@Suite("How a model introduces itself in the chooser")
struct ModelPortraitTests {
    @Test("every model in the catalog has a line written about it")
    func everyModelHasASummary() {
        for model in ModelCatalog.all {
            let portrait = ModelPortrait.of(model)
            #expect(portrait != nil, "no portrait written for \(model.id)")
            #expect(portrait?.summary.isEmpty == false, "empty summary for \(model.id)")
        }
    }

    /// The entries whose sample has not been rendered yet.
    ///
    @Test("every model has a picture of its own bundled")
    func everyModelHasASample() {
        // The one thing that stops a model shipping with a blank card. The chooser degrades to
        // a plain panel rather than a hole, so nothing else would notice.
        for model in ModelCatalog.all {
            guard let name = ModelPortrait.of(model)?.sampleName else { continue }
            #expect(NSImage(named: name) != nil, "no image set named \(name)")
        }
    }

    @Test("a sample is named after the model it came from")
    func sampleNamesFollowTheIdentifier() {
        #expect(
            ModelPortrait.of(ModelCatalog.zImageTurbo8bit)?.sampleName
                == "Sample-z-image-turbo-8bit")
    }

    @Test("a model the app has written nothing about has no portrait rather than a blank one")
    func anUnknownModelHasNoPortrait() {
        #expect(ModelPortrait.of(PreviewModel.video) == nil)
    }
}
