import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol
@testable import ZephraLinkClient
@testable import ZephraEngine

/// Transport measurements include mock hosts and clients in one process, with no inference.
@MainActor @Suite(.serialized)
struct LiveMultiHostPerformanceTests {
    @Test(.enabled(if: ["tcp", "relay"].contains(ProcessInfo.processInfo.environment["ZEPHRA_LIVE_PERFORMANCE"] ?? "")))
    func bulkPreviewAndReconnectStorm() async throws {
        let relay = ProcessInfo.processInfo.environment["ZEPHRA_LIVE_PERFORMANCE"] == "relay"
        let run = LiveMultiHostRun()
        do {
            try await run.start(count: 8, relay: relay)
            try await measure(run)
            await run.stop()
        } catch { await run.stop(); throw error }
    }
    private func measure(_ run: LiveMultiHostRun) async throws {
        for (index, row) in run.clients.enumerated() { try await row[0].setPreviews(index == 0) }
        let bytes = Data(repeating: 0x42, count: 2_097_152)
        for bed in run.beds { try bytes.write(to: bed.engine.directory.appending(path: "same.png")) }
        var peakFootprint = QualificationMemory.footprint()
        let baselineFootprint = peakFootprint
        let sampling = Task {
            while !Task.isCancelled {
                peakFootprint = max(peakFootprint, QualificationMemory.footprint())
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { sampling.cancel() }
        let start = ContinuousClock.now
        let downloads = Task {
            try await withThrowingTaskGroup(of: Int.self) { group in
                for row in run.clients { group.addTask { try await row[0].file(name: "same.png").count } }
                var total = 0
                for try await count in group { total += count }
                return total
            }
        }
        defer { downloads.cancel() }
        run.log("performance waiting for bulk admission")
        try await run.wait { run.budgets[0].reservedBytes > 0 }
        run.log("performance publishing watched preview")
        run.beds[0].store.state = .generating(.init(phase: .denoising(step: 1, of: 10), fraction: 0.1))
        run.beds[0].host.publishNow()
        let previewStarted = ContinuousClock.now
        run.beds[0].store.livePreview = CompanionPreviewTests.frame(0x44, edge: 64)
        try await run.wait { run.clients[0][0].preview != nil }
        let previewLatency = previewStarted.duration(to: .now)
        run.log("performance preview received")
        let received = try await downloads.value
        run.log("performance downloads complete; reconnecting all clients")
        #expect(received == bytes.count * 8)
        #expect(run.budgets[0].peakReservedBytes <= run.budgets[0].limit)
        #expect(run.budgets[0].reservedBytes == 0)
        let bulkTime = start.duration(to: .now)
        let stormStarted = ContinuousClock.now
        await withTaskGroup(of: Void.self) { group in
            for row in run.clients { for client in row { group.addTask {
                await client.disconnect(); await client.connect()
            } } }
        }
        try await run.wait { run.clients.flatMap { $0 }.allSatisfy(\.supportsMultiHost) }
        let stormTime = stormStarted.duration(to: .now)
        run.log("PERFORMANCE hosts=8 clients=16 downloadedBytes=\(received) bulk=\(bulkTime) preview=\(previewLatency) peakAnnouncedBytes=\(run.budgets[0].peakReservedBytes) reconnect=\(stormTime) baselineProcessFootprint=\(baselineFootprint) peakProcessFootprint=\(peakFootprint)")
    }
}
