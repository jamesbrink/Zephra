import Foundation
import ZephraCore

/// Moving pictures along the strip. The order is the order the model reads them in, so a drag is
/// a choice rather than a presentation, and it settles like every other change to the well.
extension GenerationStore {
    /// Moves one picture, which is what a drag along the strip does: the order is the order the
    /// model reads them in, so it is a choice rather than a presentation.
    public func moveReference(from index: Int, to destination: Int) {
        guard settings.referenceImages.indices.contains(index),
              (0...settings.referenceImages.count).contains(destination),
              index != destination
        else { return }
        let previous = settings.referenceImages.first
        let picture = settings.referenceImages.remove(at: index)
        settings.referenceImages.insert(
            picture, at: destination > index ? destination - 1 : destination)
        settleAfterReferenceChange(previousFirst: previous)
    }

    /// The same, in the shape a list's `onMove` hands it over. Written out rather than taken
    /// from SwiftUI, whose `move(fromOffsets:toOffset:)` this layer may not reach for.
    public func moveReferences(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let strip = settings.referenceImages
        guard !offsets.isEmpty, offsets.allSatisfy(strip.indices.contains),
              (0...strip.count).contains(destination)
        else { return }
        let previous = strip.first
        let moved = offsets.map { strip[$0] }
        var kept = strip.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let landing = destination - offsets.filter { $0 < destination }.count
        kept.insert(contentsOf: moved, at: landing)
        settings.referenceImages = kept
        settleAfterReferenceChange(previousFirst: previous)
    }
}
