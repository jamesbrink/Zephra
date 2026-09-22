import Foundation
import UIKit
import ZephraCore
import ZephraLinkProtocol

/// The two frozen states whose capsule is worth photographing with a strip in it.
///
/// The count is raised **on the snapshot rather than in the fixture file**, the way `lostRun`
/// raises `modelLoading`: the bundled fixture stays a Mac from before several pictures were
/// possible, so every other frozen state still exercises the decoder's `1...1` fallback — which
/// is the answer a real older Mac gives and the one that trims a strip to its first picture.
///
/// The pictures are drawn at launch for `page`'s own reason: a photograph of two particular
/// references would prove nothing about a strip that draws whatever is put in it. What matters
/// is that the tiles are unmistakably two and are different shapes.
extension MobilePreview {
    /// Whether this launch opens with pictures already in the well.
    static var showsReferenceStrip: Bool { state == .capsule || state == .settings }

    /// The same snapshot with its model reading up to ten pictures rather than one.
    static func severalReferences(_ snapshot: StateSnapshot) -> StateSnapshot {
        var snapshot = snapshot
        snapshot.model.capabilities.referenceImageCount = 1...10
        snapshot.models = snapshot.models.map { model in
            guard model.id == snapshot.model.id else { return model }
            var model = model
            model.capabilities.referenceImageCount = 1...10
            return model
        }
        return snapshot
    }

    /// Two pictures for the strip, in the order the model would read them.
    static func referenceStrip() -> [ReferencePicture] {
        [(3, CGSize(width: 512, height: 512)), (5, CGSize(width: 640, height: 384))]
            .compactMap { number, size in
                guard let data = page(number: number, size: size).pngData() else { return nil }
                return ReferencePicture(
                    data: data, origin: nil,
                    size: ImageSize(width: Int(size.width), height: Int(size.height)))
            }
    }

    /// Fills the capsule's well for the states that show one, and leaves every other launch's
    /// draft exactly as it was.
    static func seed(_ draft: PromptDraft) {
        guard showsReferenceStrip, let snapshot = snapshot() else { return }
        draft.replaceReferences(
            referenceStrip(),
            fitting: severalReferences(snapshot).model.capabilities.capabilities)
    }
}
