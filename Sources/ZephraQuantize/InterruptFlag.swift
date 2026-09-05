import Dispatch
import Foundation
import Synchronization

/// Whether ^C has been pressed, asked between tensors so a build stops where it is.
///
/// The default `SIGINT` disposition kills the process mid-write and leaves a `.partial`
/// directory of gigabytes behind. Ignoring the signal and reading it through a dispatch
/// source instead turns it into a flag the packer's `shouldContinue` hook can read, and the
/// throw from that hook is what lets `SnapshotBuild` remove the partial before the tool exits.
/// A second ^C while the current tensor finishes is answered by the same flag, so the build
/// is never killed part way through a file.
final class InterruptFlag: Sendable {
    private let raised = Atomic<Bool>(false)
    private let source: DispatchSourceSignal

    init() {
        signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        // Unowned rather than captured: the flag lives for the whole run, and `Atomic` cannot
        // be copied into a closure.
        source.setEventHandler { [unowned self] in
            raised.store(true, ordering: .sequentiallyConsistent)
        }
        source.resume()
    }

    /// Whether the build has been asked to stop.
    var isRaised: Bool { raised.load(ordering: .sequentiallyConsistent) }

    /// The packer's `shouldContinue` hook: throws `CancellationError` once ^C has been pressed.
    func checkContinue() throws {
        if isRaised { throw CancellationError() }
    }
}
