import Foundation
import Hub
import Testing
import ZImage
import ZephraCore
import ZephraSnapshot

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
    }

    @Test("a refused request is blamed on the token, because every catalog model is public")
    func refusedRequestsNameTheToken() {
        guard
            case let .downloadFailed(message) = ZImageErrorMapping.downloadError(
                .authorizationRequired("mzbac/public"), descriptor: descriptor)
        else {
            Issue.record("expected downloadFailed")
            return
        }
        #expect(message == HubToken.refusalMessage())
        #expect(message.contains("token") || message.contains("login"))
    }

    @Test("a transfer that broke keeps the library's reason and says a retry resumes")
    func brokenTransfersAreDownloadFailures() {
        let underlying = CocoaError(.fileNoSuchFile)
        let broken = ModelResolutionError.downloadFailed("mzbac/Z-Image-Turbo-8bit", underlying)
        guard
            case let .downloadFailed(message) = ZImageErrorMapping.downloadError(
                broken, descriptor: descriptor)
        else {
            Issue.record("expected downloadFailed")
            return
        }
        #expect(message.hasPrefix(underlying.localizedDescription), "the system's sentence, not its domain and code")
        #expect(message.hasSuffix("Try again to pick up where it left off."))
    }

    @Test("only answers that will not change stop the retrying")
    func permanentErrorsAreTheAnswersNotTheAccidents() {
        #expect(ZImageErrorMapping.isPermanent(ModelResolutionError.modelNotFound("x")))
        #expect(ZImageErrorMapping.isPermanent(ModelResolutionError.authorizationRequired("x")))
        #expect(!ZImageErrorMapping.isPermanent(ModelResolutionError.networkUnavailable))
        #expect(
            !ZImageErrorMapping.isPermanent(
                ModelResolutionError.downloadFailed("x", URLError(.networkConnectionLost))))
        #expect(
            ZImageErrorMapping.isPermanent(
                ModelResolutionError.downloadFailed("x", Hub.HubClientError.httpStatusCode(404))))
        #expect(
            !ZImageErrorMapping.isPermanent(
                ModelResolutionError.downloadFailed("x", Hub.HubClientError.httpStatusCode(503))))
        #expect(
            !ZImageErrorMapping.isPermanent(
                ModelResolutionError.downloadFailed("x", Hub.HubClientError.httpStatusCode(429))))
        #expect(
            ZImageErrorMapping.isPermanent(
                ModelResolutionError.downloadFailed("x", Hub.HubClientError.authorizationRequired)))
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

@Suite("ZImageErrorMapping speaks for the library")
struct ZImageErrorReasonTests {
    @Test("the library's offline wording is replaced with the app's, and a URL error keeps the system's")
    func offlineAndURLErrorsReadWell() {
        let descriptor = ModelCatalog.zImageTurbo8bit
        guard
            case let .downloadFailed(offline) = ZImageErrorMapping.downloadError(
                .networkUnavailable, descriptor: descriptor)
        else {
            Issue.record("expected downloadFailed")
            return
        }
        #expect(offline.hasPrefix("This Mac is offline"))
        #expect(!offline.contains("Please"))
        let lost = ZImageErrorMapping.reason(for: URLError(.networkConnectionLost))
        #expect(lost == URLError(.networkConnectionLost).localizedDescription)
        let metered = ZImageErrorMapping.reason(
            for: HubApi.EnvironmentError.offlineModeError("Repository not available locally"))
        #expect(metered.hasPrefix("This Mac is offline"))
    }
}
