import Foundation
import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

@Suite("Where a clicked notification goes")
struct NoticeDestinationTests {
    private let saved = BackgroundNotice.imageSaved(
        prompt: "a harbour in the rain", isClip: false, fileName: "zephra-2026-09-15-5eed.png")

    /// The strings a library destination is, as a notification would carry them.
    private func carried(_ fileName: String) -> [AnyHashable: Any] {
        NoticeDestination.library(fileName: fileName).userInfo
            .reduce(into: [AnyHashable: Any]()) { $0[$1.key] = $1.value }
    }

    @Test("only the saved picture names somewhere; every other notice is about the window")
    func onlyTheSavedPictureHasADestination() {
        #expect(saved.destination == .library(fileName: "zephra-2026-09-15-5eed.png"))
        #expect(BackgroundNotice.downloadFinished(model: "M").destination == nil)
        #expect(BackgroundNotice.downloadFailed(model: "M", reason: "no").destination == nil)
        #expect(
            BackgroundNotice.updateAvailable(version: "0.1.0", build: "202609120231")
                .destination == nil)
    }

    @Test("a clip's notice names its poster the same way a picture's does")
    func aClipNamesItsPoster() {
        let clip = BackgroundNotice.imageSaved(
            prompt: "the cat turns", isClip: true, fileName: "zephra-clip.png")
        #expect(clip.title == "Clip Saved")
        #expect(clip.destination == .library(fileName: "zephra-clip.png"))
    }

    @Test("a destination goes through a notification's userInfo and comes back the same")
    func roundTripsThroughUserInfo() {
        let destination = NoticeDestination.library(fileName: "a picture.png")
        #expect(NoticeDestination(userInfo: carried("a picture.png")) == destination)
    }

    @Test("a notice's own userInfo is what comes back, so the two halves cannot drift")
    func theNoticesOwnUserInfoRoundTrips() {
        guard let userInfo = saved.destination?.userInfo else {
            Issue.record("the saved picture has a destination")
            return
        }
        #expect(NoticeDestination(userInfo: userInfo) == saved.destination)
    }

    @Test("userInfo this build cannot read is no destination rather than a wrong one")
    func unreadableUserInfoIsNoDestination() {
        #expect(NoticeDestination(userInfo: [:]) == nil)
        #expect(NoticeDestination(userInfo: ["something": "else"]) == nil)
        let keys = carried("a.png")
        // A kind from some later build, carried with a name this one would otherwise take.
        let wrongKind = keys.mapValues { value -> Any in
            (value as? String) == "library" ? "album" : value
        }
        #expect(NoticeDestination(userInfo: wrongKind) == nil)
        // The kind with an empty name, which names no picture.
        let nameless = keys.mapValues { value -> Any in
            (value as? String) == "a.png" ? "" : value
        }
        #expect(NoticeDestination(userInfo: nameless) == nil)
        // The kind with no name at all: the other key, on its own.
        let kindOnly = keys.filter { ($0.value as? String) == "library" }
        #expect(kindOnly.count == 1, "the kind is one key of its own")
        #expect(NoticeDestination(userInfo: kindOnly) == nil)
        // Values of a type `[AnyHashable: Any]` allows and a notification would not.
        let numbers = keys.mapValues { _ in 7 }
        #expect(NoticeDestination(userInfo: numbers) == nil)
    }

    @Test("the notice a save is worth is named by the file, not by the prompt")
    func theSavedNoticeTakesItsNameFromTheFile() {
        let url = URL(filePath: "/Users/someone/Pictures/Zephra/zephra-2026-09-15-5eed.png")
        let notice = BackgroundNotice.saved(at: url, image: Self.image(prompt: "a harbour in the rain"))
        #expect(notice.destination == .library(fileName: "zephra-2026-09-15-5eed.png"))
        #expect(notice.title == "Image Saved")
        #expect(notice.body == "a harbour in the rain")
    }

    @Test("a save the session's history has let go still names its file")
    func aSaveWithNoRecordStillNamesItsFile() {
        let notice = BackgroundNotice.saved(
            at: URL(filePath: "/Users/someone/Pictures/Zephra/orphan.png"), image: nil)
        #expect(notice.destination == .library(fileName: "orphan.png"))
        #expect(notice.title == "Image Saved")
        #expect(notice.body == "Saved to your library.")
    }

    @Test("a clip the session made is called one, and still names its poster")
    func aSavedClipIsCalledOne() {
        let url = URL(filePath: "/Users/someone/Pictures/Zephra/a-clip.png")
        let notice = BackgroundNotice.saved(at: url, image: Self.image(prompt: "waves", frames: 49))
        #expect(notice.title == "Clip Saved")
        #expect(notice.destination == .library(fileName: "a-clip.png"))
    }

    /// One finished picture, or a clip's poster when it is worth more than a frame.
    private static func image(prompt: String, frames: Int = 1) -> GeneratedImage {
        GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: prompt,
                size: ImageSize(width: 1024, height: 1024),
                steps: 8,
                guidance: 0,
                seed: 42,
                frames: frames),
            modelID: "z-image-turbo-8bit",
            duration: .seconds(3))
    }
}
