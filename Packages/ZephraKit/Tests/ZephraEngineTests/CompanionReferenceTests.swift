import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// The pictures a phone sends before the request that names them: what a session holds until
/// the request arrives, what it puts back, and what it refuses.
///
/// A held blob is not readable from here, so every rule is checked through what the request is
/// answered with: a picture the session still holds is one the request can name, and a picture
/// it dropped is `notFound` by its position.
@MainActor
@Suite("A phone's reference pictures, on the Mac's side")
struct CompanionReferenceTests {
    private static func picture(_ byte: UInt8, bytes: Int = 64) -> Data {
        Data(repeating: byte, count: bytes)
    }

    /// A paired phone on a bed that has bootstrapped, which is what every test here starts from.
    private static func phone(_ bed: CompanionTestBed) async throws -> FakePhone {
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        return phone
    }

    @Test("ten pictures all survive until the request that names them arrives")
    func tenBlobsSurvive() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)

        var ids: [UUID] = []
        for index in 0..<ReferenceLimits.maximumPictures {
            ids.append(try await phone.sendPicture(Self.picture(UInt8(index + 1))))
        }
        var request = CompanionHostTests.request()
        request.referenceBlobIDs = ids

        guard case .error(let error) = try await phone.request(.enqueue(request)) else {
            Issue.record("ten pictures were taken by a model that reads one")
            await bed.shutdown()
            return
        }
        // The refusal is about the count and not about a missing picture, which is what says
        // every one of the ten was still held when the request naming them arrived.
        #expect(error.code == .badRequest)
        #expect(error.reason.contains("reference picture"))
        await bed.shutdown()
    }

    @Test("an eleventh picture drops the oldest, which the request then cannot name")
    func theOldestIsDropped() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)

        var ids: [UUID] = []
        for index in 0...(ReferenceLimits.maximumPictures + 2) {
            ids.append(try await phone.sendPicture(Self.picture(UInt8(index % 251))))
        }
        var request = CompanionHostTests.request()
        request.referenceBlobID = ids[0]

        guard case .error(let error) = try await phone.request(.enqueue(request)) else {
            Issue.record("a picture the session should have dropped was still there")
            await bed.shutdown()
            return
        }
        #expect(error.code == .notFound)
        await bed.shutdown()
    }

    @Test("a request naming a picture that never arrived says which one")
    func aMissingPictureIsNamedByPosition() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)

        let first = try await phone.sendPicture(Self.picture(1))
        var request = CompanionHostTests.request()
        request.referenceBlobIDs = [first, UUID()]

        guard case .error(let error) = try await phone.request(.enqueue(request)) else {
            Issue.record("a request naming a picture nobody sent was taken")
            await bed.shutdown()
            return
        }
        #expect(error.code == .notFound)
        #expect(error.reason.contains("Picture 2"), "the position is what the phone can act on")
        await bed.shutdown()
    }

    @Test("a phone that names one picture is answered exactly as it always was")
    func oneBlobStillWorks() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)

        var request = CompanionHostTests.request()
        request.referenceBlobID = try await phone.sendPicture(Self.picture(1))

        guard case .queued = try await phone.request(.enqueue(request)) else {
            Issue.record("a one-picture request was refused")
            await bed.shutdown()
            return
        }
        await bed.shutdown()
    }

    @Test("a strict submit whose picture is not what it declared is refused")
    func aMismatchedInputIsRefused() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)
        let job = try await Self.strict(
            bed, phone: phone, pictures: [Self.picture(1)],
            inputs: [GenerationInput(data: Self.picture(9))])

        guard case .error(let error) = try await phone.request(.multiHost(.submit(job))) else {
            Issue.record("a submit whose picture does not match what it declared was taken")
            await bed.shutdown()
            return
        }
        #expect(error.code == .badRequest)
        #expect(error.reason.contains("Picture 1"))
        await bed.shutdown()
    }

    @Test("a strict submit naming more blobs than it declared inputs is refused")
    func blobsWithoutInputsAreRefused() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)
        let job = try await Self.strict(bed, phone: phone, pictures: [Self.picture(1)], inputs: [])

        guard case .error(let error) = try await phone.request(.multiHost(.submit(job))) else {
            Issue.record("a submit carrying a picture it never declared was taken")
            await bed.shutdown()
            return
        }
        #expect(error.code == .badRequest)
        await bed.shutdown()
    }

    /// A strict generation the store would otherwise admit, carrying `pictures` as blobs and
    /// declaring `inputs`: everything but the pictures is in order, so what a refusal is about
    /// is the pictures.
    private static func strict(
        _ bed: CompanionTestBed, phone: FakePhone, pictures: [Data], inputs: [GenerationInput]
    ) async throws -> StrictGeneration {
        let model = bed.store.descriptor
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "a lighthouse at dusk"
        var ids: [UUID] = []
        for picture in pictures { ids.append(try await phone.sendPicture(picture)) }
        let request = GenerationRequest(
            modelID: model.id, count: 1, settings: settings, referenceBlobIDs: ids)
        return StrictGeneration(request: request, inputs: inputs)
    }

    @Test("an offer for four pictures is refused by a model that reads one")
    func anOfferForSeveralIsJudgedByTheCount() async throws {
        let bed = CompanionTestBed()
        let phone = try await Self.phone(bed)
        let model = bed.store.descriptor
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "four pictures and one model that reads one"
        let job = StrictGeneration(
            request: GenerationRequest(modelID: model.id, count: 1, settings: settings),
            inputs: (1...4).map { GenerationInput(data: Self.picture(UInt8($0))) })

        guard case .multiHost(.offer(let offer)) = try await phone.request(.multiHost(.offer(job)))
        else {
            Issue.record("the offer was not answered")
            await bed.shutdown()
            return
        }
        #expect(offer.refusal != nil, "one stand-in per input is what makes this answerable")
        #expect(offer.requiresInputTransfer == true)
        await bed.shutdown()
    }
}
