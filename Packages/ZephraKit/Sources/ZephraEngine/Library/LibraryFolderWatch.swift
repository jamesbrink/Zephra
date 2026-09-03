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
/// something nobody can see any more.
public final class LibraryFolderWatch: Sendable {
    private struct State {
        var source: (any DispatchSourceFileSystemObject)?
        var isCancelled = false
    }

    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "io.zephra.library-watch")
    private let state = Mutex(State())

    /// Watches `url`, calling `onChange` on a background queue whenever something in it moves.
    /// A folder that is not there is watched by nobody: build another once it exists.
    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        attach()
    }

    deinit { cancel() }

    /// Stops watching. Called for you when the watch is released.
    public func cancel() {
        let source = state.withLock { state -> (any DispatchSourceFileSystemObject)? in
            state.isCancelled = true
            defer { state.source = nil }
            return state.source
        }
        source?.cancel()
    }

    private func attach() {
        let descriptor = Darwin.open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handle(source.data)
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        let replaced = state.withLock { state -> (any DispatchSourceFileSystemObject)? in
            guard !state.isCancelled else { return source }
            defer { state.source = source }
            return state.source
        }
        replaced?.cancel()
        if state.withLock({ $0.isCancelled }) {
            source.cancel()
        } else {
            source.resume()
        }
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
