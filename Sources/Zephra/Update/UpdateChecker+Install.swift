import Foundation
import Synchronization
import ZephraSnapshot

extension UpdateChecker {
    /// Fetches the release on the banner, verifies it, swaps it in and relaunches.
    ///
    /// **Nothing is fetched before this is pressed.** A few hundred megabytes on a Mac's
    /// behalf, because it happened to be six hours, is not a thing to spend without being
    /// asked; `available` is where a found release sits until somebody says so.
    ///
    /// The task is held, so `cancelInstall()` has something to cancel: a Mac that has lost its
    /// network sits on a bar that is not moving, and a bar with no way out is the thing people
    /// force-quit an app over.
    func updateNow(bundle: URL = Bundle.main.bundleURL) {
        guard case .available(let release) = phase else { return }
        imageToShow = nil
        installTask = Task { await install(release, into: bundle) }
    }

    /// Stops a download in flight and puts the release back on the banner to be pressed again.
    ///
    /// Only while the bytes are coming down. Once the swap has started there is nothing safe to
    /// cancel — the bundle has been renamed aside — which is also why `Task.detached` runs it:
    /// a detached task is nobody's child, so cancelling this one cannot reach it.
    func cancelInstall() {
        guard case .downloading(let release, _) = phase else { return }
        installTask?.cancel()
        installTask = nil
        phase = .available(release)
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
            let installed = try await swap(image, of: release, into: bundle)
            // Quits through `NSApp.terminate`, so `AppLifecycle` runs the ordinary shutdown.
            // `isInstalling` is already false by here, so the quit is not deferred on itself.
            Relaunch.afterExit(of: ProcessInfo.processInfo.processIdentifier, open: installed)
        } catch is CancellationError {
            phase = .available(release)
        } catch {
            fail(error, image: fetched)
        }
        installTask = nil
    }

    /// The uninterruptible half: verify the mounted image and swap the bundle.
    ///
    /// `isInstalling` is raised around it and lowered whichever way it ends, because that flag
    /// is what `AppLifecycle` holds Quit open for — the window in which there is no `Zephra.app`
    /// where there was one.
    private func swap(
        _ image: URL, of release: ReleaseManifest, into bundle: URL
    ) async throws -> URL {
        let identifier = RunningBuild.identifier
        let overridden = environment.isOverridden
        isInstalling = true
        defer { isInstalling = false }
        return try await Task.detached {
            try UpdateInstaller.install(
                image: image, manifest: release, bundle: bundle, identifier: identifier,
                overridden: overridden)
        }.value
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
            Task { @MainActor in
                // A cancelled download can still report its last chunk; it must not put the
                // bar back up over the release the cancel returned to.
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(release, fraction: fraction)
            }
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
