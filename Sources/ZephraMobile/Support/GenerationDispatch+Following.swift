import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

/// Following the run the last press queued, so the line under Generate is the Mac's phase
/// while it renders and nothing once it is over (`RunFollowing`).
extension GenerationDispatch {
    /// What the followed run is doing, or nil when there is no run to speak of.
    var runNote: String? { following?.note }

    /// Follows a run the Mac has accepted, reading its snapshot now and on every change.
    func follow(_ batchID: UUID, on host: HostConnection) {
        stopFollowing()
        following = RunFollowing(batchID: batchID, hostName: host.name)
        let client = host.client
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                let changed = Self.changes(in: client)
                guard let self else { return }
                if let snapshot = client.snapshot { following?.read(snapshot) }
                if following?.hasEnded != false { following = nil; return }
                for await _ in changed { break }
            }
        }
    }

    /// Forgets the followed run, as the next press does.
    func stopFollowing() {
        followTask?.cancel()
        followTask = nil
        following = nil
    }

    /// Waits for the client's snapshot to be about to change.
    private static func changes(in client: LinkClient) -> AsyncStream<Void> {
        AsyncStream<Void> { sink in
            withObservationTracking {
                _ = client.snapshot
            } onChange: {
                sink.yield(())
                sink.finish()
            }
        }
    }
}
