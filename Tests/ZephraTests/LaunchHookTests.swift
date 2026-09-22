import Foundation
import Testing
import ZephraCore

@testable import Zephra

/// `ZEPHRA_GENERATE_ON_LAUNCH` and `ZEPHRA_REFERENCE_ON_LAUNCH`, gated the way
/// `ZEPHRA_PREVIEW_STATE` is: inert in Release, whatever the environment says. The parsing
/// itself is pure (`resolvedPrompt(from:)`, `resolvedReference(from:)`) and is what these pin;
/// the Debug gate around `prompt` is compiled out here too, since `make test-app` only runs
/// Debug, so the Release half of the claim rests on reading `#if DEBUG` in the source, the same
/// way `InterfacePreviewTests` cannot run a Release build either.
@Suite("The launch-on-boot debugging hooks")
struct LaunchHookTests {
    @Test("the prompt is the variable's value, and nothing when it is unset or empty")
    func resolvesThePrompt() {
        #expect(LaunchGeneration.resolvedPrompt(from: [:]) == nil)
        #expect(LaunchGeneration.resolvedPrompt(from: ["ZEPHRA_GENERATE_ON_LAUNCH": ""]) == nil)
        #expect(
            LaunchGeneration.resolvedPrompt(from: ["ZEPHRA_GENERATE_ON_LAUNCH": "a red bicycle"])
                == "a red bicycle")
    }

    @Test("the reference is a file URL over the variable's path, and nothing when it is unset or empty")
    func resolvesTheReference() {
        #expect(LaunchGeneration.resolvedReference(from: [:]) == nil)
        #expect(LaunchGeneration.resolvedReference(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": ""]) == nil)
        #expect(
            LaunchGeneration.resolvedReference(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/ref.png"])
                == URL(filePath: "/tmp/ref.png"))
    }

    @Test("a colon separates several pictures, in the order they are named")
    func resolvesSeveralReferences() {
        #expect(LaunchGeneration.resolvedReferences(from: [:]).isEmpty)
        #expect(
            LaunchGeneration.resolvedReferences(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": ""]).isEmpty)
        let three = LaunchGeneration.resolvedReferences(
            from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/a.png:/tmp/b.png:/tmp/c.png"])
        #expect(three.map(\.path) == ["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"])
    }

    @Test("an empty segment is not a picture, so a trailing colon names nothing extra")
    func emptySegmentsAreDropped() {
        let urls = LaunchGeneration.resolvedReferences(
            from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/a.png::/tmp/b.png:"])
        #expect(urls.map(\.path) == ["/tmp/a.png", "/tmp/b.png"])
    }

    @Test("the list stops at what the limits carry")
    func theListIsTrimmed() {
        let named = (1...20).map { "/tmp/\($0).png" }.joined(separator: ":")
        #expect(
            LaunchGeneration.resolvedReferences(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": named]).count
                == ReferenceLimits.maximumPictures)
    }

    @Test("one picture still reads as one picture, which is what the hook has always meant")
    func oneIsStillOne() {
        #expect(
            LaunchGeneration.resolvedReference(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/ref.png"])
                == URL(filePath: "/tmp/ref.png"))
        #expect(
            LaunchGeneration.resolvedReference(
                from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/a.png:/tmp/b.png"])
                == URL(filePath: "/tmp/a.png"))
    }

    @Test("the frozen strip holds two pictures unless the environment says otherwise")
    func theFrozenStripCounts() {
        #expect(InterfacePreview.referenceCount(in: [:]) == 2)
        #expect(InterfacePreview.referenceCount(in: ["ZEPHRA_PREVIEW_REFERENCES": "10"]) == 10)
        #expect(InterfacePreview.referenceCount(in: ["ZEPHRA_PREVIEW_REFERENCES": "0"]) == 0)
        // Nothing an environment variable says may put the window in a state the app could not
        // reach: past the limit is the limit, and words are not numbers.
        #expect(
            InterfacePreview.referenceCount(in: ["ZEPHRA_PREVIEW_REFERENCES": "99"])
                == ReferenceLimits.maximumPictures)
        #expect(InterfacePreview.referenceCount(in: ["ZEPHRA_PREVIEW_REFERENCES": "-3"]) == 0)
        #expect(InterfacePreview.referenceCount(in: ["ZEPHRA_PREVIEW_REFERENCES": "lots"]) == 2)
    }

    @Test("a launch naming only a reference and no prompt asks for nothing")
    func referenceAloneIsNotARequest() {
        // `resolvedReference` alone answers a path; it is `run(on:)`'s guard on `prompt` that
        // makes a picture with no prompt do nothing, which is a doc comment's claim and not
        // something the pure parsing functions can pin on their own.
        #expect(LaunchGeneration.resolvedPrompt(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/ref.png"]) == nil)
    }
}
