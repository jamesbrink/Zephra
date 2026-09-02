import Testing
import ZephraCore

@Suite("ModelAvailability")
struct ModelAvailabilityLabelTests {
    @Test("a download is labelled with its size, to one decimal place")
    func downloadLabel() {
        #expect(ModelAvailability.needsDownload(bytes: 13_280_000_000).label == "13.3 GB download")
        #expect(ModelAvailability.needsDownload(bytes: 7_000_000_000).label == "7 GB download")
    }

    @Test("what is on disk and what cannot be had read differently")
    func plainLabels() {
        #expect(ModelAvailability.available.label == "Downloaded")
        #expect(ModelAvailability.missing(reason: "no such folder").label == "Not built yet")
    }

    @Test("the reason behind a missing model survives for a tooltip")
    func reasonIsKept() {
        #expect(ModelAvailability.missing(reason: "no such folder").reason == "no such folder")
        #expect(ModelAvailability.available.reason == nil)
    }

    @Test("only a download needs the network, and only a missing model cannot be had")
    func flags() {
        #expect(ModelAvailability.needsDownload(bytes: 1).needsNetwork)
        #expect(ModelAvailability.available.needsNetwork == false)
        #expect(ModelAvailability.available.isObtainable)
        #expect(ModelAvailability.needsDownload(bytes: 1).isObtainable)
        #expect(ModelAvailability.missing(reason: "x").isObtainable == false)
    }
}
