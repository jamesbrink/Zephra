import Foundation
import Observation
import ZephraCore
import ZephraSnapshot

/// What the catalog's models occupy on this Mac, as the Settings window observes it: each
/// directory, its size, and the total, with a way to send one to the Trash.
///
/// Reading the list is one directory listing per model and is done on the main actor;
/// measuring is a walk over every file and is not. So the items appear at once with their
/// sizes blank, and each size lands as its walk finishes. A removal is followed by a fresh
/// read, so the list is always what the disk says rather than what was believed a moment ago.
@MainActor
@Observable
public final class ModelInventory {
    /// Every directory found, in catalog order, sizes filled in as they are measured.
    public private(set) var items: [ModelStorageItem] = []
    /// True while any size is still being measured.
    public private(set) var isMeasuring = false
    /// The most recent removal that failed, phrased for the person reading it, or nil.
    public private(set) var lastFailure: String?

    @ObservationIgnored private let catalog: [ModelDescriptor]
    @ObservationIgnored private let cache: URL
    private var locations: ModelLocations
    @ObservationIgnored private let remove: @Sendable (ModelStorageItem) throws -> Void
    @ObservationIgnored private var generation = 0

    /// An inventory over `catalog`, reading `locations` and the hub cache. The defaults are
    /// the real places; a test passes a scratch folder and a `remove` that spares the Trash.
    public init(
        catalog: [ModelDescriptor] = ModelCatalog.all,
        cache: URL = HubCache.directory(),
        locations: ModelLocations = .default,
        remove: @escaping @Sendable (ModelStorageItem) throws -> Void = ModelStorage.remove
    ) {
        self.catalog = catalog
        self.cache = cache
        self.locations = locations
        self.remove = remove
    }

    /// The sum of every measured size.
    public var totalBytes: Int64 { items.reduce(0) { $0 + ($1.bytes ?? 0) } }

    /// The folder models are kept in, for the window to show and open.
    public var modelsDirectory: URL { locations.root }

    /// Keeps models in `locations` from now on. The list is not re-read here: the caller
    /// refreshes, so a change of folder is one read of the disk rather than two.
    public func setLocations(_ locations: ModelLocations) {
        self.locations = locations
    }

    /// Reads the directories again and measures each. A refresh under way is superseded: its
    /// sizes are dropped rather than written over the new list.
    public func refresh() async {
        generation += 1
        let mine = generation
        let found = ModelStorage.items(for: catalog, cache: cache, locations: locations)
        items = found
        isMeasuring = !found.isEmpty
        for item in found {
            let bytes = await Task.detached(priority: .utility) { ModelStorage.measure(item.url) }.value
            guard mine == generation else { return }
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].bytes = bytes
            }
        }
        if mine == generation { isMeasuring = false }
    }

    /// Sends the item's directory to the Trash and reads the list again. A failure is kept in
    /// `lastFailure` and the list re-read anyway, since the disk may have changed part-way.
    public func delete(_ item: ModelStorageItem) async {
        lastFailure = nil
        do {
            try remove(item)
        } catch {
            lastFailure = "Couldn't move \(item.name) to the Trash. \(error.localizedDescription)"
        }
        await refresh()
    }
}
