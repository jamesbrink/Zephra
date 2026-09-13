import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

extension LibraryCatalog {
    func addHost(_ id: HostID, client: LinkClient, frozen: Bool) -> LibraryCatalog {
        if let child = children[id] { return child }
        let root = frozen ? nil : libraryRoot?.appending(path: "Hosts/" + id.rawValue)
        let child = LibraryCatalog(libraryRoot: root, filesRoot: nil, sharedFiles: fileStore)
        child.hostID = id
        children[id] = child
        child.changed = { [weak self] in self?.combine() }
        child.start(client: client)
        return child
    }
    func removeHost(_ id: HostID) async {
        guard let child = children.removeValue(forKey: id) else { return }
        sourceFilters.remove(id)
        child.changed = nil
        await child.stopAndDrain()
        await child.entryStore.clear()
        await child.thumbnailStore.clear()
        await fileStore.remove(prefix: id.rawValue + "-")
        combine()
    }
    func combine() {
        isLive = children.values.contains { $0.isLive }
        isSyncing = children.values.contains { $0.isSyncing }
        publish(children.values.flatMap(\.entries))
    }
    func owner(of entry: CachedEntry) -> LibraryCatalog? {
        entry.hostID.flatMap { children[$0] }
    }
    func isLive(for entry: CachedEntry) -> Bool {
        if let id = entry.hostID, id != hostID { return children[id]?.isLive ?? false }
        return isLive
    }
    func lease(_ entry: CachedEntry) async -> FileLease {
        let key = mediaKey(entry, fallback: entry.fileName)
        return await fileStore.lease(entry.isVideo ? Self.clipName(of: key) : key)
    }
    func mediaKey(_ entry: CachedEntry?, fallback: String) -> String {
        guard let entry, let id = entry.hostID else { return fallback }
        return id.rawValue + "-" + GenerationInput.digest(Data((entry.fileName + ":" + entry.version).utf8)) + ".png"
    }
    /// Names are composite identities at the aggregate boundary, ordinary filenames on the wire.
    func partition(_ ids: [String]) -> [(LibraryCatalog, [String])] {
        let entries = ids.compactMap(entry(named:))
        return children.compactMap { id, child in
            let names = entries.filter { $0.hostID == id }.map(\.fileName)
            return names.isEmpty ? nil : (child, names)
        }
    }
}
