import Foundation
import ZephraCore

@testable import ZephraEngine
@testable import ZephraSnapshot

extension EngineTestBed {
    /// Whether the pool still holds the claim the last `ensureAvailable` was handed.
    func holdsClaim(_ store: GenerationStore) async -> Bool {
        guard let id = control.settings.lastAcquisitionID else { return false }
        return await store.downloads.transfers.claims[id] != nil
    }

    /// How many claims the pool holds right now, whichever model they are for.
    func claimCount(_ store: GenerationStore) async -> Int {
        await store.downloads.transfers.claims.count
    }
}
