import Foundation

/// The selected run's pictures, resolved on the Mac that owns the opened entry.
enum TodayPictures {
    @MainActor
    static func entries(around entry: CachedEntry, hosts: [HostConnection]) -> [CachedEntry] {
        guard let host = hosts.first(where: { $0.id == entry.hostID }),
            let run = host.client.snapshot?.today.first(where: { $0.fileNames.contains(entry.fileName) })
        else { return [entry] }
        let pictures = run.fileNames.compactMap(host.catalog.entry(named:))
        // Keep the opening valid if a library update has removed it since the tap.
        return pictures.contains(where: { $0.id == entry.id }) ? pictures : [entry]
    }
}
