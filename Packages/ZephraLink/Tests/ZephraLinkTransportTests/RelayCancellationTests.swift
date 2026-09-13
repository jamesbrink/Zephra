import Foundation
import Network
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkTransport

@Suite("Cancelling a relay opening closes its pending WebSocket")
struct RelayCancellationTests {
    @Test func heldUpgrade() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let (accepted, sink) = AsyncStream<NWConnection>.makeStream()
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            sink.yield(connection)
        }
        listener.start(queue: .global())
        defer { listener.cancel(); sink.finish() }
        let deadline = ContinuousClock.now + .seconds(5)
        while (listener.port?.rawValue ?? 0) == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let port = try #require(listener.port)
        let road = RelayConnection(url: URL(string: "wss://127.0.0.1:\(port.rawValue)")!,
            identity: DeviceIdentity(), room: DeviceIdentity().roomID, role: .guest, joinDeadline: .seconds(30))
        let opening = Task {
            do { try await road.start() } catch { print("Relay cancellation fixture opening: \(error)"); sink.finish(); throw error }
        }
        let timeout = Task { try? await Task.sleep(for: .seconds(5)); sink.finish() }
        defer { timeout.cancel(); opening.cancel() }
        var iterator = accepted.makeAsyncIterator()
        let socket = try #require(await iterator.next())
        defer { socket.cancel() }
        let cancelled = ContinuousClock.now
        opening.cancel()
        do { try await opening.value; Issue.record("Cancelled relay join succeeded") } catch {}
        #expect(cancelled.duration(to: .now) < .seconds(3), "Cancellation must not wait for the 30-second join deadline")
        #expect(road.lock.withLock { road.state.isClosed })
    }
}
