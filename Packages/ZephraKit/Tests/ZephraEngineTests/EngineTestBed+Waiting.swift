import Foundation
import ZephraCore

@testable import ZephraEngine

extension EngineTestBed {
    /// Blocks until `condition` holds, polling every couple of milliseconds, and throws after
    /// `timeout` so a test that never gets there fails on its own terms rather than hanging.
    func waitUntil(
        _ timeout: Duration = .seconds(15), _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                throw BackendError.loadFailed("Test barrier timed out")
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
