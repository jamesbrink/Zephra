import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("The store refuses a load or a run this Mac has not the memory for")
struct MemoryGuardStoreTests {
    /// A 16 GB Mac's working set, which no catalog model is held whole in.
    static let small = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 12_124 << 20)

    /// A budget the catalog straddles: klein 4-bit runs tiled, Z-Image 8-bit and Qwen-Image
    /// stream, and LTX-2.5 with sound is over even its streamed figure, so it is a model this
    /// Mac cannot hold and the one every "cannot hold" case below is about. Z-Image 8-bit is
    /// what `bootstrap` therefore keeps here, streamed, since its 6.42 GB streamed peak was
    /// measured on 2026-09-13; before that it was tight and the store stepped onto klein.
    static let straddling = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 11_000_000_000)

    /// The catalog entry that budget cannot hold.
    static let tooLarge = ModelCatalog.ltx2DistilledAudio4bit

    /// A model no Mac in the catalog's world can hold, whichever lever is pulled.
    static let unholdable = ModelDescriptor(
        id: "unholdable", displayName: "Unholdable", variantName: nil, backend: .zImage,
        source: ModelCatalog.default.source, quantization: .int4, downloadBytes: 0,
        residentBytes: 60_000_000_000, peakBytes: 90_000_000_000,
        tiledPeakBytes: 80_000_000_000, streamedPeakBytes: 0, maxPromptTokens: 512,
        capabilities: ModelCatalog.default.capabilities, builtBytes: 0, adapters: [])

    static func starved() -> MachineMemory {
        MachineMemory(physicalBytes: 16 << 30, availableBytes: 400_000_000)
    }

    @Test("a load the machine has no room for fails with the sentence, and loads nothing")
    func aLoadWithNoRoomIsRefused() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        bed.machineMemory = Self.starved()

        await store.bootstrap()

        guard case .failed(let error) = store.state,
            case .insufficientMemory(let shortfall) = error
        else {
            Issue.record("expected a memory refusal, got \(store.state)")
            return
        }
        #expect(shortfall.phase == .load)
        #expect(shortfall.modelName == store.descriptor.fullName)
        #expect(error.message == shortfall.sentence)
        #expect(bed.control.settings.loads == 0, "the weights must never be read")
        #expect(store.loadedDescriptor == nil)
        // The disk lease is given back, or Settings > Models would show a folder in use for
        // the rest of the session over a load that never happened.
        #expect(store.acquiredModel?.id == nil)
    }

    @Test("Retry once the memory is back loads the model the refusal left alone")
    func retryOnceTheMemoryIsBack() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        bed.machineMemory = Self.starved()
        await store.bootstrap()
        #expect(bed.control.settings.loads == 0)

        bed.machineMemory = MachineMemory(
            physicalBytes: 128_000_000_000, availableBytes: 120_000_000_000)
        store.retry()
        await store.bootstrapTask?.value

        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == 1)
        #expect(store.loadedDescriptor?.id == store.descriptor.id)
    }

    @Test("a run the machine has no room for is refused, and the queue does not sit behind it")
    func aRunWithNoRoomEmptiesTheQueue() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.state == .ready)

        bed.machineMemory = Self.starved()
        store.settings.prompt = "a cat"
        store.generate(count: 2)
        await store.generationTask?.value

        guard case .failed(let error) = store.state,
            case .insufficientMemory(let shortfall) = error
        else {
            Issue.record("expected a memory refusal, got \(store.state)")
            return
        }
        #expect(shortfall.phase == .run)
        #expect(store.queue.isEmpty)
        #expect(store.running == nil)
        #expect(bed.control.settings.generations == 0)
    }

    @Test("a model this Mac cannot hold is never loaded, whatever names it")
    func anUnholdableModelIsNeverLoaded() async throws {
        let bed = EngineTestBed()
        bed.memoryBudget = Self.small
        let store = bed.store(descriptor: Self.unholdable)
        store.warmsUpAfterLoad = false

        await store.load(Self.unholdable, asSwap: false)

        guard case .failed(.insufficientMemory) = store.state else {
            Issue.record("expected a memory refusal, got \(store.state)")
            return
        }
        #expect(bed.control.settings.loads == 0)
        #expect(bed.control.settings.availabilityChecks == 0, "nothing is even looked for")
    }

    @Test("picking a model this Mac cannot hold does nothing at all")
    func switchingToAnUnholdableModelIsANoOp() async throws {
        let bed = EngineTestBed()
        bed.memoryBudget = Self.small
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let before = store.descriptor.id

        store.switchModel(to: Self.unholdable)

        #expect(store.descriptor.id == before)
        #expect(store.state == .ready)
    }

    @Test("a picture from a model this Mac cannot hold keeps the model in use")
    func aPictureFromAnUnholdableModelKeepsTheCurrentModel() async throws {
        let bed = EngineTestBed()
        bed.memoryBudget = Self.straddling
        let store = bed.store(descriptor: ModelCatalog.flux2Klein4bit)
        var settings = GenerationSettings.defaults(for: ModelCatalog.qwenImage2512_4bit)
        settings.prompt = "from another Mac"

        // A picture from a model this Mac can hold chooses that model, as it always has.
        store.select(
            GeneratedImage(
                pngData: Data(), settings: settings, modelID: ModelCatalog.qwenImage2512_4bit.id,
                duration: .seconds(1)))
        #expect(store.descriptor.id == ModelCatalog.qwenImage2512_4bit.id)

        // One from a model it cannot hold is still shown, and its settings are still taken —
        // on the current model's schedule, exactly as a picture from a dropped model is.
        store.select(
            GeneratedImage(
                pngData: Data(), settings: settings, modelID: Self.tooLarge.id,
                duration: .seconds(1)))
        #expect(store.descriptor.id == ModelCatalog.qwenImage2512_4bit.id)
        #expect(store.current != nil)
        #expect(store.settings.prompt == "from another Mac")
    }

    @Test("a phone is told which of the two refusals it has met")
    func aPhoneIsToldWhichRefusal() async throws {
        let bed = EngineTestBed()
        bed.memoryBudget = Self.straddling
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        var settings = GenerationSettings.defaults(for: store.descriptor)
        settings.prompt = "a cat"

        // A model this Mac can never hold is the request's own fault: no wait fixes it.
        let never = store.remoteAdmission(for: Self.tooLarge, settings: settings)
        guard case .badRequest(let sentence) = never else {
            Issue.record("expected a bad request, got \(never)")
            return
        }
        #expect(sentence.hasPrefix("\(Self.tooLarge.fullName) needs"))

        // A machine that is simply full right now is worth asking again in a moment. The model
        // in force here is streamed — since 2026-09-13 Z-Image 8-bit fits this budget that way,
        // so `bootstrap` keeps it rather than stepping onto klein — and a streamed load is
        // charged its whole peak where MLX has allocated nothing yet, since the descriptor's
        // resident figure is not what such a load holds — it is larger than the streamed peak
        // itself. Subtracting it would floor the transient at zero and admit this run on a Mac
        // with 400 MB free.
        bed.machineMemory = Self.starved()
        let busy = store.remoteAdmission(for: store.descriptor, settings: settings)
        guard case .refused(let reason) = busy else {
            Issue.record("expected a refusal, got \(busy)")
            return
        }
        #expect(reason.hasSuffix("Quit other apps and retry."))
        #expect(store.enqueue(settings, on: store.descriptor) == nil)
        #expect(store.queue.isEmpty)
    }
}
