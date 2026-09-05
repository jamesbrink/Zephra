import Foundation
import ZephraCore

extension ModelTransfers {
    func reservedBytes(on volume: String) -> Int64 {
        transfers.values.filter { $0.volume == volume }.reduce(0) { $0 + $1.remainingBytes }
            + builds.values.filter { $0.volume == volume }.reduce(0) { $0 + $1.bytes }
    }

    /// Retained for the whole build; newly admitted downloads account for it too.
    public func reserveBuild(_ id: UUID, bytes: Int64, at root: URL) throws {
        guard claims[id] != nil else { throw CancellationError() }
        guard bytes > 0 else { return }
        let volume = try capacity(root)
        if let free = volume.available, free < bytes + reservedBytes(on: volume.id) + (256 << 20) {
            throw BackendError.loadFailed("Not enough space to build while downloads are active. Pause a download or free space, then Retry.")
        }
        builds[id] = (volume.id, bytes)
    }

    public func finishBuild(_ id: UUID) { builds.removeValue(forKey: id) }
}
