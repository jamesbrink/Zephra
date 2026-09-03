import Foundation
import Synchronization

/// Notices when a folder changes, including from outside the app.
///
/// A `DispatchSource` on the directory's own descriptor rather than a timer: the Finder deleting
/// an image, another Mac's sync writing one in, or Zephra's own save all arrive the same way and
/// within a moment. It says only "something happened" — the index takes a fingerprint to find
/// out whether that something matters.
///
/// The descriptor is reopened when the folder itself is renamed, deleted, or has its volume
/// pulled: an fd survives its directory being replaced, which would leave the watch pointing at
/// something nobody can see any more. If the folder is not there to reopen — renamed away, on a
/// volume that has just been ejected — the watch keeps trying, backing off to eight seconds, for
/// as long as it is alive. A watch that gave up would be indistinguishable from a folder that
/// never changes again.
public final class LibraryFolderWatch: Sendable {
    private struct State {
        var source: (any DispatchSourceFileSystemObject)?
        var isCancelled = false
        var backoff: Duration
    }

    /// How long to wait before the first attempt to reopen a folder that is not there.
    public static let firstRetry = Duration.milliseconds(500)
    /// The longest it ever waits between attempts.
    public static let maximumRetry = Duration.seconds(8)

    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "io.zephra.library-watch")
    private let state: Mutex<State>
    private let firstRetry: Duration
    private let maximumRetry: Duration

    /// Watches `url`, calling `onChange` on a background queue whenever something in it moves.
    /// The retry delays are parameters only so a test does not have to wait half a second.
    public init(
        url: URL,
        firstRetry: Duration = LibraryFolderWatch.firstRetry,
        maximumRetry: Duration = LibraryFolderWatch.maximumRetry,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.onChange = onChange
        self.firstRetry = firstRetry
        self.maximumRetry = maximumRetry
        self.state = Mutex(State(backoff: firstRetry))
        attach()
    }

    deinit { cancel() }

    /// Whether this watch has been stopped. A stopped watch never starts again, so the index
    /// treats one as no watch at all and builds another.
    public var isCancelled: Bool { state.withLock { $0.isCancelled } }

    /// Stops watching, and stops retrying. Called for you when the watch is released.
    public func cancel() {
        let source = state.withLock { state -> (any DispatchSourceFileSystemObject)? in
            state.isCancelled = true
            defer { state.source = nil }
            return state.source
        }
        source?.cancel()
    }

    /// Opens the folder and starts a source on it, or schedules another try when it is not there.
    ///
    /// A watch that comes back after the folder was away announces a change whether or not one
    /// arrived: everything that happened while there was nothing to watch went unreported, and
    /// the listener has no other way to find out.
    private func attach(notifying: Bool = false) {
        let descriptor = Darwin.open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            retryLater()
            return
        }
        defer { if notifying { onChange() } }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handle(source.data)
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        let cancelled = state.withLock { state -> Bool in
            guard !state.isCancelled else { return true }
            state.source?.cancel()
            state.source = source
            state.backoff = firstRetry
            return false
        }
        if cancelled {
            source.cancel()
        } else {
            source.resume()
        }
    }

    private func retryLater() {
        let delay = state.withLock { state -> Duration? in
            guard !state.isCancelled else { return nil }
            state.source?.cancel()
            state.source = nil
            let delay = state.backoff
            state.backoff = min(state.backoff * 2, maximumRetry)
            return delay
        }
        guard let delay else { return }
        queue.asyncAfter(deadline: .now() + Self.interval(delay)) { [weak self] in
            self?.attach(notifying: true)
        }
    }

    /// A `Duration` as Dispatch wants it.
    private static func interval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        return .nanoseconds(Int(seconds * 1_000_000_000 + attoseconds / 1_000_000_000))
    }

    /// The folder going away is the one event that needs more than a notification: the old
    /// descriptor still refers to something, just not to anything anyone can reach.
    private func handle(_ events: DispatchSource.FileSystemEvent) {
        if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
            attach()
        }
        onChange()
    }
}
