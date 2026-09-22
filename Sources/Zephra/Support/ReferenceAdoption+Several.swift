import Foundation
import ZephraCore
import ZephraEngine

/// The same doors, opened with an armful of pictures rather than one.
///
/// Every one of them is **one** claim and **one** landing (`GenerationStore.adoptReferences`): a
/// drop of five files is a single choice, and five claims under five tickets would land only the
/// last — which is precisely the failure the ticket exists to prevent.
///
/// A door handed exactly one picture goes through the single-picture door instead, so that the
/// one rule "Use as Reference adds a picture where there is room and replaces the whole strip
/// where there is not" stays where it is written, in `GenerationStore.useAsReference`. Handed
/// several, the store takes as many as the model and the budget allow and says in
/// `referenceNote` when it took fewer — which is the honest answer for a door that cannot mean
/// "start afresh with these five" and "add these five" at the same time.
extension ReferenceAdoption {
    /// Library pictures the caller already has in hand: the picker sheet's selection.
    @MainActor
    static func adopt(_ items: [LibraryItem], into store: GenerationStore) {
        guard items.count != 1 else { return adopt(items[0], into: store) }
        guard !items.isEmpty else { return }
        store.adoptReferences { items.compactMap(picture(of:)) }
    }

    /// Library pictures named only by their ids — a drop of several `LibraryItemReference`s.
    @MainActor
    static func adopt(ids: [LibraryItem.ID], into store: GenerationStore) {
        guard ids.count != 1 else { return adopt(id: ids[0], into: store) }
        guard !ids.isEmpty else { return }
        store.adoptReferences { ids.compactMap(picture(atPath:)) }
    }

    /// Files dropped from the Finder, or chosen in the open panel.
    @MainActor
    static func adopt(urls: [URL], into store: GenerationStore) {
        guard urls.count != 1 else {
            store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: urls[0]) }
            return
        }
        guard !urls.isEmpty else { return }
        store.adoptReferences { urls.compactMap { ReferenceImageEncoder.picture(contentsOf: $0) } }
    }

    /// Picture bytes dropped from another app.
    @MainActor
    static func adopt(bytes: [Data], into store: GenerationStore) {
        guard bytes.count != 1 else {
            store.adoptReference { ReferenceImageEncoder.pngData(from: bytes[0]) }
            return
        }
        guard !bytes.isEmpty else { return }
        store.adoptReferences { bytes.compactMap { ReferenceImageEncoder.picture(from: $0) } }
    }

    /// One library item as reference bytes, by `adopt(_ item:into:)`'s own rule: an edit hands
    /// back the picture it was made from, not itself. Off the main actor, since it reads a file.
    nonisolated static func picture(of item: LibraryItem) -> ReferencePicture? {
        let record = item.provenance.record
        let origin = record?.referenceBytes != nil ? record?.referenceOrigin : item.fileName
        if let source = item.referenceImage {
            return ReferenceImageEncoder.picture(from: source, origin: origin)
        }
        return ReferenceImageEncoder.picture(contentsOf: item.url, origin: origin)
    }

    /// One dropped library path as reference bytes, by `adopt(id:into:)`'s own rule.
    nonisolated static func picture(atPath path: LibraryItem.ID) -> ReferencePicture? {
        let url = URL(fileURLWithPath: path)
        let origin = referenceOrigin(droppedFrom: url)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let reference = GenerationRecord.reference(in: data) {
            return ReferenceImageEncoder.picture(from: reference, origin: origin)
        }
        return ReferenceImageEncoder.picture(from: data, origin: origin)
    }
}
