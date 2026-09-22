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
    /// An entry belongs here only between the commit that adds it to the catalog and the
    /// `scripts/make-samples.sh` run that draws its card, which needs the packed variant on the
    /// Mac and a generation at forty steps. The list is what keeps that gap visible instead of
    /// silent, and it is checked against the catalog below so a stale name fails too.
    static let awaitingSample: Set<ModelDescriptor.ID> = ["qwen-image-2.1-4bit"]

    @Test("every model has a picture of its own bundled, or is named as still owing one")
    func everyModelHasASample() {
        // The one thing that stops a model shipping with a blank card. The chooser degrades to
        // a plain panel rather than a hole, so nothing else would notice.
        for model in ModelCatalog.all where !Self.awaitingSample.contains(model.id) {
            guard let name = ModelPortrait.of(model)?.sampleName else { continue }
            #expect(NSImage(named: name) != nil, "no image set named \(name)")
        }
        for id in Self.awaitingSample {
            #expect(
                ModelCatalog.descriptor(id: id) != nil,
                "\(id) is no longer in the catalog; take it out of awaitingSample")
            #expect(
                NSImage(named: "Sample-\(id)") == nil,
                "\(id) has its sample now; take it out of awaitingSample")
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
