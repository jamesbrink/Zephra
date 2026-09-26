import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkClient

@MainActor
@Suite("Large upscales reach the phone intact")
struct LargeFileTransferTests {
    @Test("An encrypted file transfer above 64 MiB fits the admitted budget")
    func largeFile() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        let payload = Data(repeating: 173, count: 65 * 1024 * 1024)
        bed.host.payload = payload
        await bed.client.connect()
        let received = try await bed.client.file(name: "upscaled.png")
        #expect(received == payload)
        #expect(bed.client.blobBudget.reservedBytes == 0)
        #expect(BlobBudget().fileLimit == BlobReassembly.byteCap)
    }
}
