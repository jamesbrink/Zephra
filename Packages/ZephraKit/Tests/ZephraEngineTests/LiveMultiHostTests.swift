import Foundation
import Testing

/// Disabled in ordinary tests: the relay case explicitly contacts the deployed relay.
@MainActor @Suite(.serialized)
struct LiveMultiHostTests {
    nonisolated static var counts: [Int] {
        if let value = ProcessInfo.processInfo.environment["ZEPHRA_UAT_HOSTS"], let count = Int(value), [1, 2, 4, 8].contains(count) { return [count] }
        return [1, 2, 4, 8]
    }
    @Test(.enabled(if: ["tcp", "relay"].contains(ProcessInfo.processInfo.environment["ZEPHRA_LIVE_UAT"] ?? "")),
          arguments: counts)
    func liveTopology(_ count: Int) async throws {
        let relay = ProcessInfo.processInfo.environment["ZEPHRA_LIVE_UAT"] == "relay"
        let run = LiveMultiHostRun()
        let start = ContinuousClock.now
        do {
            try await run.start(count: count, relay: relay)
            try await run.exercise()
            await run.stop()
        } catch {
            await run.stop()
            throw error
        }
        let elapsed = start.duration(to: .now)
        print("MULTI_HOST_UAT transport=\(relay ? "relay" : "tcp") hosts=\(count) phones=2 seconds=\(elapsed) phase=finished")
    }
}
