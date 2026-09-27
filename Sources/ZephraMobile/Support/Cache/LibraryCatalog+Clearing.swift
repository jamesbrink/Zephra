import Foundation

extension LibraryCatalog {
    /// Pause all children before suspending; shared media is cleared only once.
    func clearCache() async {
        if let clearing { await clearing.value; return }
        let catalogs = children.isEmpty ? [self] : [self] + Array(children.values)
        for catalog in catalogs { catalog.isClearing = true; catalog.stop() }
        let task = Task { @MainActor in
            for catalog in catalogs { await catalog.drain() }
            let targets = children.isEmpty ? catalogs : [self] + Array(children.values)
            for catalog in targets {
                await catalog.entryStore.clear()
                await catalog.thumbnailStore.clear()
                catalog.publish([])
            }
            await fileStore.clear()
            let resumed = children.isEmpty ? [self] : [self] + Array(children.values)
            for catalog in resumed {
                catalog.pendingDeletions.removeAll()
                catalog.isClearing = false
                if let client = catalog.client {
                    await catalog.sync(with: client)
                    catalog.start(client: client)
                }
            }
            await measureCache()
        }
        clearing = task
        await task.value
        clearing = nil
    }

    func drain() async {
        while operations > 0 { try? await Task.sleep(for: .milliseconds(5)) }
    }
}
