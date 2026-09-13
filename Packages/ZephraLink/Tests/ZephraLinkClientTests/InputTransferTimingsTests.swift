import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkClient

@Suite("Reference transfer costs remain unknown until observed on this session")
struct InputTransferTimingsTests {
    @Test func estimates() {
        var timings = InputTransferTimings()
        #expect(timings.estimate(bytes: 1000) == nil)
        timings.record(bytes: 1000, seconds: 2)
        #expect(timings.estimate(bytes: 2000) == 4.8)
        #expect(timings.estimate(bytes: 10) == 2.4, "Fixed admission and acknowledgment latency cannot scale to zero")
        for _ in 0..<8 { timings.record(bytes: 1000, seconds: 1) }
        #expect(timings.estimate(bytes: 2000) == 2.4)
        #expect(InputTransferTimings().estimate(bytes: 2000) == nil)
    }
    @Test func malformedComponents() {
        let id = HostID(keys: DevicePublicKeys(keyAgreement: Data(), signing: Data([1])))
        for value in [-1.0, .nan, .infinity] {
            var offer = HostOffer(refusal: nil, queueSeconds: 0, preparationSeconds: 0,
                executionSeconds: 10, memoryMargin: 1, modelLoaded: true, queueCount: 0,
                queueRevision: "1", physicalMemory: 1)
            offer.finalizationSeconds = value
            #expect(!HostCandidate(id: id, offer: offer).eligible)
            offer.finalizationSeconds = 0
            offer.inputTransferSeconds = value
            #expect(!HostCandidate(id: id, offer: offer).eligible)
        }
    }
    @Test func unknownReferencePreventsETA() {
        var offer = HostOffer(refusal: nil, queueSeconds: 0, preparationSeconds: 0,
            executionSeconds: 10, memoryMargin: 1, modelLoaded: true, queueCount: 0,
            queueRevision: "1", physicalMemory: 1, finalizationSeconds: 2,
            requiresInputTransfer: true, timingSampleCount: 4)
        #expect(offer.totalSeconds == nil)
        #expect(offer.estimateConfidence == "unknown")
        offer.inputTransferSeconds = 3
        #expect(offer.totalSeconds == 15)
        #expect(offer.estimateConfidence == "measured")
    }
}
