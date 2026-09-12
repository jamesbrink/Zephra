import Foundation
import Testing
import ZephraCore
import ZephraEngine
@testable import Zephra

@Suite("Which engine transitions are worth a notification")
struct BackgroundNoticeTests {
    private let downloading = EngineState.downloading(
        DownloadProgressEvent(completedFiles: 1, totalFiles: 4, fraction: 0.25))

    @Test("a download that ends in a build, a load or a ready model finished")
    func finished() {
        for next in [EngineState.loading(.preparing), .warmingUp, .ready] {
            #expect(BackgroundNotice.transition(from: downloading, to: next, model: "M") == .downloadFinished(model: "M"))
        }
    }

    @Test("a download that ends in a failure failed, with the reason")
    func failed() {
        let notice = BackgroundNotice.transition(from: downloading, to: .failed(.noBackend(.zImage)), model: "M")
        guard case .downloadFailed(let model, let reason)? = notice else {
            Issue.record("expected a failure notice, got \(String(describing: notice))")
            return
        }
        #expect(model == "M")
        #expect(!reason.isEmpty)
    }

    @Test("a download the person stopped, and anything that was not a download, says nothing")
    func silent() {
        #expect(BackgroundNotice.transition(from: downloading, to: .cancelling, model: "M") == nil)
        #expect(BackgroundNotice.transition(from: downloading, to: .idle, model: "M") == nil)
        #expect(BackgroundNotice.transition(from: .ready, to: .failed(.noBackend(.zImage)), model: "M") == nil)
        #expect(BackgroundNotice.transition(from: .loading(.preparing), to: .ready, model: "M") == nil)
    }

    @Test("a saved image is named by its prompt, and a clip is called one")
    func savedImage() {
        let notice = BackgroundNotice.imageSaved(prompt: "a cat on a limestone wall", isClip: false)
        #expect(notice.title == "Image Saved")
        #expect(notice.body == "a cat on a limestone wall")
        let clip = BackgroundNotice.imageSaved(prompt: "the cat turns", isClip: true)
        #expect(clip.title == "Clip Saved")
    }

    @Test("a published update names the build, since every version is 0.1.0")
    func updateAvailable() {
        let notice = BackgroundNotice.updateAvailable(version: "0.1.0", build: "202609120231")
        #expect(notice.title == "Update Available")
        #expect(notice.body == "Zephra 0.1.0 (build 202609120231) is ready to install.")
    }

    @Test("the banner's prompt is one line, cut at a word, and never empty")
    func promptSummary() {
        #expect(BackgroundNotice.summary(of: "  a cat\n\non   a wall ") == "a cat on a wall")
        #expect(BackgroundNotice.summary(of: "") == "Saved to your library.")
        #expect(BackgroundNotice.summary(of: "\n \t") == "Saved to your library.")
        let long = Array(repeating: "word", count: 40).joined(separator: " ")
        let summary = BackgroundNotice.summary(of: long)
        #expect(summary.hasSuffix("…"))
        #expect(summary.count <= BackgroundNotice.summaryLength + 1)
        #expect(!summary.contains("wor…"), "cut at a word, not through one")
        let oneWord = String(repeating: "x", count: 140)
        #expect(BackgroundNotice.summary(of: oneWord) == String(repeating: "x", count: 100) + "…")
    }
}
