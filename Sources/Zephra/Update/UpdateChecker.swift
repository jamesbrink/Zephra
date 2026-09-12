import Foundation
import Observation
import ZephraSnapshot
import os

/// Whether a newer Zephra has been published, and how far along installing it is.
///
/// `@MainActor @Observable`, built once in the composition root and handed down as an
/// environment value — never a singleton, which `ModelCatalog` alone is allowed to be. The
/// window's banner, the menu item and Settings all read this one object.
///
/// The snooze is **the session's only**. With no version bumps, a build written to disk as
/// "skipped" would be a build number the next check compares against nothing, and the honest
/// implementations of a persisted skip all end up silencing the ship after it too. A person
/// who presses Later gets their window back until they relaunch.
@MainActor @Observable
final class UpdateChecker {
    /// How long after launch the first check runs: long enough to be behind the window, the
    /// model survey and the first load.
    static let launchDelay = Duration.seconds(10)
    /// And how often after that.
    static let interval = Duration.seconds(6 * 60 * 60)

    /// Only this type writes these three; `private(set)` is not spelled because
    /// `UpdateChecker+Install.swift` is the other half of it and a file-private setter would
    /// shut that half out.
    var phase: UpdatePhase = .idle
    var snoozedBuild: String?
    /// The verified disk image behind a failure that is worth showing in the Finder, so a Mac
    /// whose Applications folder cannot be written to still has something to drag.
    var imageToShow: URL?

    /// Whether the swap is happening right now — the window in which there is no `Zephra.app`
    /// where there was one. `AppLifecycle` holds Quit open on it; nothing draws it, so it is
    /// deliberately outside observation.
    @ObservationIgnored var isInstalling = false
    /// The download and install in flight, held so Cancel has something to cancel.
    @ObservationIgnored var installTask: Task<Void, Never>?

    @ObservationIgnored let environment: UpdateEnvironment
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var notifiedBuild: String?
    @ObservationIgnored let log = Logger(subsystem: "io.zephra", category: "update")

    init(environment: UpdateEnvironment = .current) {
        self.environment = environment
    }

    /// A checker standing still in one phase, for `ZEPHRA_PREVIEW_STATE=update` and the
    /// `#Preview`s. It has no timer and never reaches the network.
    static func frozen(_ phase: UpdatePhase) -> UpdateChecker {
        let checker = UpdateChecker()
        checker.phase = phase
        return checker
    }

    /// Whether the banner belongs on screen right now.
    var showsBanner: Bool {
        UpdateDecision.showsBanner(phase: phase, snoozedBuild: snoozedBuild)
    }

    /// Starts the launch check and the six-hourly one after it, unless this launch has no
    /// business checking at all.
    ///
    /// A frozen preview build returns first and returns silently: a screenshot build must
    /// never reach the network, which is the same rule `startCompanion` follows.
    func start() {
        guard InterfacePreview.requestedState == nil else { return }
        sweepPreviousInstall()
        let eligibility = UpdateEligibility.current(environment)
        guard eligibility.canInstall else {
            log.info("update: this copy does not update itself (\(String(describing: eligibility), privacy: .public))")
            return
        }
        guard AppSettings.flag(AppSettings.checksForUpdates) else { return }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                // Re-read at each tick, so switching the preference off stops the checking
                // rather than only stopping the next launch's.
                guard AppSettings.flag(AppSettings.checksForUpdates) else { break }
                _ = await self?.checkNow(manual: false)
                try? await Task.sleep(for: Self.interval)
            }
            // Cleared so a later `start()` can begin again, which is what switching the
            // preference back on and relaunching-free recovery both want.
            self?.stopLoop()
        }
    }

    /// Reads the feed and moves the phase on. Answers what to tell a person who pressed Check
    /// for Updates, and nil for a check nobody asked for: an alert saying everything is as it
    /// was, over the window somebody is working in, is how updates get switched off.
    @discardableResult
    func checkNow(manual: Bool) async -> UpdateOutcome? {
        // A frozen screenshot build reaches no network at all, however it is asked — the menu
        // item included. The same rule `startCompanion` follows.
        guard InterfacePreview.requestedState == nil else { return nil }
        let eligibility = UpdateEligibility.current(environment)
        guard eligibility.canInstall else {
            return manual ? .ineligible(reason: eligibility.refusal ?? "") : nil
        }
        // A download or an install in flight is not something a second check may reset.
        guard !phase.isWorking else { return nil }
        phase = .checking
        do {
            let latest = try await UpdateFeed(url: environment.feed).latest()
            let running = RunningBuild.number(pretending: environment.pretendBuild)
            guard latest.isNewer(than: running) else {
                phase = .idle
                return manual ? .upToDate(version: AppFacts.versionLine) : nil
            }
            found(latest, manual: manual)
            return manual ? .available(latest) : nil
        } catch {
            let reason = (error as? UpdateFeedError)?.message ?? error.localizedDescription
            log.error("update: the check did not finish: \(reason, privacy: .public)")
            // A failure nobody asked about is not worth a banner; one behind a menu press is
            // reported in the alert and left on the banner to be tried again.
            phase = manual ? .failed(reason: reason) : .idle
            return manual ? .failed(reason: reason) : nil
        }
    }

    /// Puts the release on the banner, and says so behind another app's window once per build.
    private func found(_ release: ReleaseManifest, manual: Bool) {
        log.info("update: \(release.line, privacy: .public) is published")
        phase = .available(release)
        // An explicit check is an explicit interest: whatever Later hid, this un-hides.
        if manual { snoozedBuild = nil }
        guard notifiedBuild != release.build else { return }
        notifiedBuild = release.build
        BackgroundNotices.post(.updateAvailable(version: release.version, build: release.build))
    }

    /// Forgets the timer, so `start()` may begin one again.
    private func stopLoop() {
        loop = nil
    }

    /// Puts the banner away. A failure is simply cleared, since there is nothing to come back
    /// to; a release is hidden for the rest of the session and offered again at the next launch.
    func later() {
        if case .failed = phase {
            phase = .idle
            imageToShow = nil
            return
        }
        snoozedBuild = phase.release?.build
    }
}
