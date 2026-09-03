import Foundation
import ZephraCore

/// Turning two lists of pictures into one list of runs: what a seed is, which of the two it came
/// from, and how the ones that carry no run of their own are put back together.
extension SessionTimeline {
    /// One image on its way to becoming a tile, flattened so an indexed file and an image this
    /// session just made are the same kind of thing from here on.
    struct Seed {
        let batchID: UUID?
        let createdAt: Date
        let prompt: String
        let size: ImageSize
        let modelID: String
        let steps: Int
        let hasReference: Bool
        let tile: TimelineTile

        /// A file the library index knows about, or nil for anything Zephra did not make.
        init?(item: LibraryItem) {
            guard let record = item.provenance.record else { return nil }
            batchID = record.batchID
            createdAt = record.createdAt
            prompt = record.prompt
            size = ImageSize(width: record.width, height: record.height)
            modelID = record.modelID
            steps = record.steps
            hasReference = record.referenceBytes != nil
            tile = .item(item)
        }

        /// An image this session made, which the index has not caught up with yet.
        init(fresh image: GeneratedImage) {
            batchID = image.batchID
            createdAt = image.createdAt
            prompt = image.settings.prompt
            size = image.settings.size
            modelID = image.modelID
            steps = image.settings.steps
            hasReference = image.settings.referenceImage != nil
            tile = .fresh(image)
        }

        /// Whether two neighbours were plainly asked for by the same press of Generate. It is
        /// what stands in for a run id on files written before there was one: the same request
        /// at the same size on the same model, one after another in the same folder.
        func belongsWith(_ other: Seed) -> Bool {
            prompt == other.prompt && modelID == other.modelID && size == other.size
                && steps == other.steps && hasReference == other.hasReference
        }
    }

    /// Today's indexed files and this session's images as one list, newest first, with the
    /// duplicates dropped.
    ///
    /// An image is in both lists for as long as it takes the folder watch to settle. The
    /// indexed copy wins, because that is the one the library, the inspector and the thumbnail
    /// cache all agree about; the session's copy is only there to fill the square sooner.
    static func seeds(
        items: [LibraryItem],
        history: [GeneratedImage],
        isToday: (Date) -> Bool
    ) -> [Seed] {
        let today = items.filter { $0.collection == .generated && isToday($0.createdAt) }
        let indexed = Set(today.map(\.id))
        var all = today.compactMap(Seed.init(item:))
        for image in history where !indexed.contains(path(of: image) ?? "") {
            all.append(Seed(fresh: image))
        }
        return all.sorted {
            $0.createdAt == $1.createdAt ? $0.tile.id > $1.tile.id : $0.createdAt > $1.createdAt
        }
    }

    /// The seeds cut into runs, newest run first, each run's own seeds still newest first.
    ///
    /// A seed that names its run is filed under it. One that does not — a file written before
    /// the record carried a run — joins the seed above it when the two were plainly the same
    /// request, and starts a run of its own otherwise.
    static func grouped(_ seeds: [Seed]) -> [(id: UUID, seeds: [Seed])] {
        var order: [UUID] = []
        var runs: [UUID: [Seed]] = [:]
        var previous: (seed: Seed, id: UUID)?
        for seed in seeds {
            let id = runID(for: seed, after: previous)
            if runs[id] == nil { order.append(id) }
            runs[id, default: []].append(seed)
            previous = (seed, id)
        }
        return order.map { (id: $0, seeds: runs[$0] ?? []) }
    }

    private static func runID(for seed: Seed, after previous: (seed: Seed, id: UUID)?) -> UUID {
        if let batch = seed.batchID { return batch }
        if let previous, previous.seed.batchID == nil, previous.seed.belongsWith(seed) {
            return previous.id
        }
        return derivedID(from: seed.tile.id)
    }

    /// Where an image sits on disk, folded the way `LibraryItem.id` is, so the two lists can be
    /// compared. Nil for an image that has not been written yet.
    private static func path(of image: GeneratedImage) -> String? {
        image.fileURL?.standardizedFileURL.path(percentEncoded: false)
    }

    /// A run id for a group that has none, from the id of the image that starts it.
    ///
    /// Derived rather than random, so the same folder produces the same runs on every rebuild
    /// and a row does not lose its identity between two frames. Two rounds of FNV-1a, which is
    /// stable across launches in a way `Hasher` deliberately is not.
    private static func derivedID(from key: String) -> UUID {
        var bytes: [UInt8] = []
        for salt: UInt64 in [0xcbf2_9ce4_8422_2325, 0x9e37_79b9_7f4a_7c15] {
            var hash = salt
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            withUnsafeBytes(of: hash.bigEndian) { bytes.append(contentsOf: $0) }
        }
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}
