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

    @Test("a saved image is named by its file, without the extension")
    func savedImage() {
        let notice = BackgroundNotice.imageSaved(URL(filePath: "/x/a-cat-42.png"))
        #expect(notice.title == "Image Saved")
        #expect(notice.body == "a-cat-42")
    }
}
