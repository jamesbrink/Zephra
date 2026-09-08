import Foundation
import Testing

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

    @Test("a launch naming only a reference and no prompt asks for nothing")
    func referenceAloneIsNotARequest() {
        // `resolvedReference` alone answers a path; it is `run(on:)`'s guard on `prompt` that
        // makes a picture with no prompt do nothing, which is a doc comment's claim and not
        // something the pure parsing functions can pin on their own.
        #expect(LaunchGeneration.resolvedPrompt(from: ["ZEPHRA_REFERENCE_ON_LAUNCH": "/tmp/ref.png"]) == nil)
    }
}
