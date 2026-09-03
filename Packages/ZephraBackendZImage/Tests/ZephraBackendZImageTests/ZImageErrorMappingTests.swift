import Foundation
import Testing
import ZImage
import ZephraCore

@testable import ZephraBackendZImage

@Suite("ZImageErrorMapping")
struct ZImageErrorMappingTests {
    private let descriptor = ModelCatalog.zImageTurbo8bit

    @Test("weights that cannot be obtained at all read as unavailable, not as a failed transfer")
    func unobtainableWeightsAreUnavailable() {
        #expect(
            ZImageErrorMapping.downloadError(.modelNotFound("mzbac/nope"), descriptor: descriptor)
                == .modelNotAvailable(descriptor.fullName)
        )
        #expect(
            ZImageErrorMapping.downloadError(
                .authorizationRequired("mzbac/gated"), descriptor: descriptor
            ) == .modelNotAvailable(descriptor.fullName)
        )
    }

    @Test("a transfer that broke stays a download failure and keeps the library's wording")
    func brokenTransfersAreDownloadFailures() {
        let offline = ZImageErrorMapping.downloadError(.networkUnavailable, descriptor: descriptor)
        #expect(offline == .downloadFailed((ModelResolutionError.networkUnavailable).readableMessage))

        let underlying = CocoaError(.fileNoSuchFile)
        let broken = ModelResolutionError.downloadFailed("mzbac/Z-Image-Turbo-8bit", underlying)
        #expect(
            ZImageErrorMapping.downloadError(broken, descriptor: descriptor)
                == .downloadFailed((broken).readableMessage)
        )
        #expect((broken).readableMessage.contains("mzbac/Z-Image-Turbo-8bit"))
    }

    @Test("the unavailable case names the model the way a picker labels it")
    func unavailableCarriesTheFullName() {
        guard
            case let .modelNotAvailable(name) = ZImageErrorMapping.downloadError(
                .modelNotFound("x"), descriptor: descriptor
            )
        else {
            Issue.record("expected modelNotAvailable")
            return
        }
        #expect(name == "Z-Image Turbo · 8-bit")
    }

    @Test("a LocalizedError contributes its own message")
    func localizedErrorsKeepTheirText() {
        let error = ModelResolutionError.modelNotFound("mzbac/nope")
        #expect((error).readableMessage == "Model not found: mzbac/nope")
    }

    @Test("errors with no message of their own fall back to the case name")
    func silentErrorsFallBackToTheCaseName() {
        // Missing weights and the other pipeline failures carry no LocalizedError text, so the
        // case name is all there is; `loadFailed`'s own wording is what the user actually reads.
        #expect((ZImagePipeline.PipelineError.modelNotLoaded).readableMessage == "modelNotLoaded")
        #expect(
            (ZImagePipeline.PipelineError.weightsMissing("dit.safetensors")).readableMessage
                .contains("dit.safetensors")
        )
    }

    @Test("cancellation still produces a non-empty message if it ever reaches the mapper")
    func cancellationHasAMessage() {
        // The backend passes CancellationError through untouched rather than mapping it, so this
        // only guards against an empty string if that path ever changes.
        #expect(!(CancellationError()).readableMessage.isEmpty)
    }
}
