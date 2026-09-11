import Foundation
import ZephraCore
import ZephraEngine

/// Turning a library picture into reference bytes and putting it in the well.
///
/// An image that was itself edited from a picture hands back that picture, not itself: "use
/// this as a reference" on an edit almost always means "let me try that again from the same
/// starting point", and handing back the edit would compound one generation onto another.
///
/// Both doors read and re-encode off the main actor, through `ReferenceImageEncoder`, so a
/// large PNG is capped at 1024 pixels along its edge before anything holds it — the app would
/// otherwise carry the whole picture in memory, hash it, and write it into every image the
/// reference goes on to make. The one place that rule lives, so the menu button, the well's own
/// menu, and the picker sheet cannot drift apart on what "use as reference" means. Which choice
/// is current is the store's own bookkeeping (`GenerationStore.claimReference`); nothing here
/// holds state, so two stores could not trip over one another's choices.
enum ReferenceAdoption {
    /// Adopts a picture the caller already has as a `LibraryItem` — the menu button and the
    /// picker sheet's own selection, which both came from the index and so already know
    /// whether it carries a reference of its own.
    ///
    /// `origin` is the SOURCE's own file name when the item hands back its source picture
    /// (nil when that source's own record carries none), and the item's own file name
    /// otherwise — the record is already in memory on `item.provenance`, so this costs no read
    /// beyond the one the closure below makes anyway.
    @MainActor
    static func adopt(_ item: LibraryItem, into store: GenerationStore) {
        let record = item.provenance.record
        let origin = record?.referenceBytes != nil ? record?.referenceOrigin : item.fileName
        store.adoptReference(origin: origin) {
            if let source = item.referenceImage {
                return ReferenceImageEncoder.pngData(from: source)
            }
            return ReferenceImageEncoder.pngData(contentsOf: item.url)
        }
    }

    /// Adopts a picture this session made and the index may not have seen yet, by the same
    /// rule as a library item: one that was itself edited from a picture hands back that
    /// picture, and the bytes are re-encoded to the reference's own cap either way, so the
    /// canvas's menu means the same thing before and after the folder scan catches up.
    ///
    /// `origin` follows the same rule as `adopt(_ item:into:)`: the source's own origin when
    /// `image` hands back its source, and `image`'s own file name otherwise.
    @MainActor
    static func adopt(_ image: GeneratedImage, into store: GenerationStore) {
        let hasSource = image.settings.referenceImage != nil
        let source = image.settings.referenceImage ?? image.pngData
        let origin = hasSource ? image.settings.referenceOrigin : image.fileURL?.lastPathComponent
        store.adoptReference(origin: origin) { ReferenceImageEncoder.pngData(from: source) }
    }

    /// Adopts a picture named only by its id — a drop of a `LibraryItemReference`, which
    /// carries nothing else. `LibraryItem.ID` is the standardized file path, so this reads the
    /// file directly rather than asking a `LibraryIndex` to resolve it first, which is what
    /// lets the well accept the drop without holding an index of its own.
    @MainActor
    static func adopt(id: LibraryItem.ID, into store: GenerationStore) {
        let url = URL(fileURLWithPath: id)
        store.adoptReference(origin: referenceOrigin(droppedFrom: url)) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let reference = GenerationRecord.reference(in: data) {
                return ReferenceImageEncoder.pngData(from: reference)
            }
            return ReferenceImageEncoder.pngData(from: data)
        }
    }

    /// The origin a drop of `LibraryItemReference` should carry: the dropped file's own name,
    /// or the file it was itself edited from, when its header says it was one.
    ///
    /// A header read (`PNGTextChunks.read(fromHeaderOf:)`, the same fast read a library scan
    /// makes) rather than the full read the closure above makes: `adoptReference`'s `origin`
    /// travels with the choice and so has to be known before the read starts, unlike the bytes
    /// themselves, which only the closure needs.
    @MainActor
    private static func referenceOrigin(droppedFrom url: URL) -> String? {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: url),
            let record = GenerationRecord.decode(from: text), record.referenceBytes != nil
        else { return url.lastPathComponent }
        return record.referenceOrigin
    }

    /// Puts `png` in the well, or clears it with nil, as a choice made right now: any library
    /// read still in flight is cancelled, so a slow picture can never land on top of a file, a
    /// drop, or a Clear that came after it.
    @MainActor
    static func use(_ png: Data?, into store: GenerationStore) {
        store.useAsReference(png, ticket: store.claimReference())
    }

    /// Sets the next generation up to animate a picture the session still holds in memory, or
    /// its clip's last frame when it is one — never the picture it started from, unlike
    /// `adopt(_:into:)` above: Animate means exactly the picture in front of you, and handing
    /// back an edit's source would animate the wrong one. `FreshImageMenu` and
    /// `FreshImageActions` both call this, so the rule lives once.
    ///
    /// A clip's last frame comes from its saved MP4 when the file has landed, and from the clip
    /// still held in memory (`image.video?.mp4`, through a temporary file) when it has not —
    /// never from the poster, which is only the *first* frame and would animate the wrong end of
    /// the clip. `ActionAvailability.hasAnimatableSource` is what greys the button in that one
    /// remaining case, a clip with neither. The frame is read through the store's own clip
    /// reader (`GenerationStore.clips`, the `ClipEditing` the root injected) and re-encoded
    /// through `ReferenceImageEncoder`, so it is capped and cast like every other door.
    @MainActor
    static func animate(_ image: GeneratedImage, into store: GenerationStore) {
        let clips = store.clips
        store.animate(origin: image.fileURL?.lastPathComponent) {
            guard image.isVideo else {
                return ReferenceImageEncoder.pngData(from: image.pngData)
            }
            if let fileURL = image.fileURL {
                return await lastFrame(of: .file(VideoSidecar.url(beside: fileURL)), clips: clips)
            }
            if let mp4 = image.video?.mp4 {
                return await lastFrame(of: .bytes(mp4), clips: clips)
            }
            return nil
        }
    }

    /// The same rule over a `LibraryItem`: its own bytes, or its clip's last frame, read off the
    /// main actor — never `item.referenceImage`, which is what makes `adopt(_:into:)` hand back
    /// an edit's source instead of the edit itself. `AnimateButton` and the menu bar's Animate
    /// command both call this.
    @MainActor
    static func animate(_ item: LibraryItem, into store: GenerationStore) {
        let clips = store.clips
        store.animate(origin: item.fileName) {
            if item.isVideo, let videoURL = item.videoURL {
                return await lastFrame(of: .file(videoURL), clips: clips)
            }
            return ReferenceImageEncoder.pngData(contentsOf: item.url)
        }
    }

    /// A clip's last frame as reference bytes, or nil when the clip cannot be read.
    private nonisolated static func lastFrame(
        of clip: ContinuationSource.Clip, clips: (any ClipEditing)?
    ) async -> Data? {
        guard let clips else { return nil }
        let frames: [Data]?
        switch clip {
        case .file(let url): frames = try? await clips.tail(of: url, frames: 1)
        case .bytes(let mp4): frames = try? await clips.tail(ofData: mp4, frames: 1)
        }
        return frames?.last.flatMap(ReferenceImageEncoder.pngData(from:))
    }

    /// Sets the next generation up to carry a library clip on from where it ends, the way
    /// `animate` sets one up from its last frame: `ExtendClipButton` and the menu bar's Extend
    /// Clip command both call this. Nothing for a picture, which has no end to carry on from.
    @MainActor
    static func extend(_ item: LibraryItem, into store: GenerationStore) {
        guard item.isVideo, let videoURL = item.videoURL, let record = item.provenance.record
        else { return }
        store.extend(ContinuationSource(origin: item.fileName, clip: .file(videoURL), record: record))
    }

    /// The same over a clip this session made. `FreshImageMenu` and `FreshImageActions` call
    /// this.
    ///
    /// Only once the clip has been written: the join at the end of the run finds the source by
    /// its library name in the images folder or Recently Deleted
    /// (`GenerationStore+Stitching`), so a clip still only in memory has nothing to be joined
    /// onto and no name to be found by. The save starts the moment the clip lands and puts the
    /// MP4 down before the poster, so the wait is a blink and the sidecar is there whenever
    /// the poster is — which is why this reads the file rather than `image.video?.mp4`.
    /// `ActionAvailability.extendDisabledReason` greys the button until then.
    @MainActor
    static func extend(_ image: GeneratedImage, into store: GenerationStore) {
        guard image.isVideo, let fileURL = image.fileURL else { return }
        store.extend(
            ContinuationSource(
                origin: fileURL.lastPathComponent, clip: .file(VideoSidecar.url(beside: fileURL)),
                record: GenerationRecord(image)))
    }
}
