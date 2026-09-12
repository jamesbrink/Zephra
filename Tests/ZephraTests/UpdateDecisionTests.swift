import Foundation
import Testing
import ZephraCore
import ZephraEngine
import ZephraSnapshot

@testable import Zephra

@Suite("When an update may be installed, and when its banner is on screen")
struct UpdateDecisionTests {
    private let release = ReleaseManifest(
        url: URL(string: "https://example.test/releases/Zephra-0.1.0-202609120231.dmg")!,
        version: "0.1.0", build: "202609120231", sha256: String(repeating: "a", count: 64))

    private let busy: [EngineState] = [
        .downloading(DownloadProgressEvent(completedFiles: 1, totalFiles: 4, fraction: 0.25)),
        .building(BuildProgressEvent(
            component: "transformer", completedComponents: 1, totalComponents: 3, fraction: 0.5)),
        .generating(GenerationProgressEvent(phase: .denoising(step: 1, of: 4), fraction: 0.25)),
        .upscaling(UpscaleProgressEvent(completedTiles: 1, totalTiles: 4)),
        .cancelling,
    ]

    private let free: [EngineState] = [
        .idle, .checkingModel, .loading(.preparing), .warmingUp, .ready, .failed(.noBackend(.zImage)),
    ]

    @Test("work that would be thrown away blocks the install, with a sentence saying which")
    func busyStatesBlock() {
        for state in busy {
            let reason = UpdateDecision.installBlockedReason(engine: state, hasActiveDownloads: false)
            #expect(reason?.isEmpty == false, "\(state) should block the install")
        }
    }

    @Test("an idle, loading or failed engine does not block it")
    func freeStatesDoNot() {
        for state in free {
            #expect(UpdateDecision.installBlockedReason(engine: state, hasActiveDownloads: false) == nil)
        }
    }

    @Test("a model downloading in the background blocks it even while the engine is ready")
    func aTransferBlocksIt() {
        #expect(UpdateDecision.installBlockedReason(engine: .ready, hasActiveDownloads: true) != nil)
        #expect(UpdateDecision.installBlockedReason(engine: .idle, hasActiveDownloads: true) != nil)
    }

    @Test("nothing found and a check in flight draw no banner")
    func quietPhasesDrawNothing() {
        #expect(!UpdateDecision.showsBanner(phase: .idle, snoozedBuild: nil))
        #expect(!UpdateDecision.showsBanner(phase: .checking, snoozedBuild: nil))
    }

    @Test("a release, its download, its install and a failure are all on screen")
    func everythingElseIsOnScreen() {
        let phases: [UpdatePhase] = [
            .available(release), .downloading(release, fraction: 0.4),
            .ready(release, image: URL(filePath: "/tmp/Zephra.dmg")), .installing(release),
            .failed(reason: "The update server answered HTTP 500."),
        ]
        for phase in phases {
            #expect(UpdateDecision.showsBanner(phase: phase, snoozedBuild: nil), "\(phase)")
        }
    }

    @Test("a release somebody pressed Later on is gone until the next one, and only that one")
    func snoozeHidesOneBuild() {
        #expect(!UpdateDecision.showsBanner(phase: .available(release), snoozedBuild: release.build))
        #expect(UpdateDecision.showsBanner(phase: .available(release), snoozedBuild: "202609112359"))
        // A failure is not a release, so a snooze cannot hide one.
        #expect(UpdateDecision.showsBanner(phase: .failed(reason: "no"), snoozedBuild: release.build))
    }

    @Test("the phase names the release it is about, and says when it is busy")
    func phaseCarriesItsRelease() {
        #expect(UpdatePhase.downloading(release, fraction: 0.1).release == release)
        #expect(UpdatePhase.ready(release, image: URL(filePath: "/tmp/a.dmg")).release == release)
        #expect(UpdatePhase.idle.release == nil)
        #expect(UpdatePhase.checking.isWorking)
        #expect(UpdatePhase.installing(release).isWorking)
        #expect(!UpdatePhase.available(release).isWorking)
    }
}
