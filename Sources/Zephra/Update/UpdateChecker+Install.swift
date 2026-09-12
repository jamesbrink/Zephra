import Foundation
import Synchronization
import ZephraSnapshot

extension UpdateChecker {
    /// Fetches the release on the banner, verifies it, swaps it in and relaunches.
    ///
    /// **Nothing is fetched before this is pressed.** A few hundred megabytes on a Mac's
    /// behalf, because it happened to be six hours, is not a thing to spend without being
    /// asked; `available` is where a found release sits until somebody says so.
    func updateNow(bundle: URL = Bundle.main.bundleURL) {
        guard case .available(let release) = phase else { return }
        imageToShow = nil
        Task { await install(release, into: bundle) }
    }

    private func install(_ release: ReleaseManifest, into bundle: URL) async {
        phase = .downloading(release, fraction: 0)
        var fetched: URL?
        do {
            let image = try await UpdateDownload().fetch(
                release, into: UpdateDownload.defaultDirectory(), onProgress: reporter(for: release))
            fetched = image
            phase = .ready(release, image: image)
            phase = .installing(release)
            let identifier = RunningBuild.identifier
            let installed = try await Task.detached {
                try UpdateInstaller.install(
                    image: image, manifest: release, bundle: bundle, identifier: identifier)
            }.value
            // Quits through `NSApp.terminate`, so `AppLifecycle` runs the ordinary shutdown.
            Relaunch.afterExit(of: ProcessInfo.processInfo.processIdentifier, open: installed)
        } catch {
            fail(error, image: fetched)
        }
    }

    /// A progress closure that hops to the main actor at most a hundred times over the whole
    /// file. The download hands back a chunk every few dozen kilobytes, and a `Task` per chunk
    /// is thousands of them for one bar that draws in whole percents.
    private func reporter(for release: ReleaseManifest) -> @Sendable (Double) -> Void {
        let last = Mutex(-1)
        return { [weak self] fraction in
            let percent = Int(fraction * 100)
            let moved = last.withLock { seen -> Bool in
                guard percent > seen else { return false }
                seen = percent
                return true
            }
            guard moved else { return }
            Task { @MainActor in self?.phase = .downloading(release, fraction: fraction) }
        }
    }

    /// Puts a failure on the banner in the words the person needs, keeping the verified disk
    /// image to offer when the only thing wrong is this Mac's own folder.
    private func fail(_ error: any Error, image: URL?) {
        let reason: String
        switch error {
        case let install as UpdateInstallError:
            reason = install.message
            imageToShow = install.offersTheDiskImage ? image : nil
        case let download as UpdateDownloadError:
            reason = download.message
        case is CancellationError:
            phase = .idle
            return
        default:
            reason = error.localizedDescription
        }
        log.error("update: the install did not finish: \(reason, privacy: .public)")
        phase = .failed(reason: reason)
    }

    /// Clears what a finished install left behind, at the next launch rather than during one:
    /// `Zephra.previous.app` beside the running bundle, and everything under `Updates/`.
    ///
    /// The running bundle is never a candidate, whatever it is called — the sweep only ever
    /// removes a sibling whose name ends in `.previous.app`, and a disk image it downloaded
    /// itself.
    func sweepPreviousInstall() {
        let files = FileManager.default
        let bundle = Bundle.main.bundleURL
        let aside = bundle.deletingLastPathComponent()
            .appending(path: bundle.deletingPathExtension().lastPathComponent + ".previous.app")
        if aside != bundle, files.fileExists(atPath: aside.path(percentEncoded: false)) {
            try? files.removeItem(at: aside)
            log.info("update: removed \(aside.lastPathComponent, privacy: .public)")
        }
        try? files.removeItem(at: UpdateDownload.defaultDirectory())
    }
}
