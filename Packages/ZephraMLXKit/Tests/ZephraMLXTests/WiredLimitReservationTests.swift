import MLX
import Testing
import ZephraMLX

@Suite("The wired-memory reservation follows its requests")
struct WiredLimitReservationTests {
    /// Reads the manager's own events, which mlx-swift emits in Debug builds only — the
    /// configuration `xcodebuild test` builds. Each event carries how many tickets were active
    /// when it was emitted, which is the one observable that tells one reservation from two.
    @Test("two wired limits set back to back leave one ticket active, the later one")
    func replacesInOrder() async throws {
        let events = await WiredMemoryManager.shared.events()
        let (first, second) = (64 << 20, 96 << 20)

        MLXRuntime.configure(cacheLimitBytes: nil, memoryLimitBytes: nil, wiredLimitBytes: first)
        MLXRuntime.configure(cacheLimitBytes: nil, memoryLimitBytes: nil, wiredLimitBytes: second)

        let started = await withTaskGroup(of: [WiredMemoryEvent].self) { group in
            group.addTask {
                var seen: [WiredMemoryEvent] = []
                for await event in events where event.kind == .ticketStarted {
                    seen.append(event)
                    if seen.count == 2 { break }
                }
                return seen
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return []
            }
            let winner = await group.next() ?? []
            group.cancelAll()
            return winner
        }

        #expect(started.map(\.size) == [first, second])
        let last = try #require(started.last)
        #expect(last.size == second)
        #expect(last.activeCount == 1)
    }
}
