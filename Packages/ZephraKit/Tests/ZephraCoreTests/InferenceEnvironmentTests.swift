import Testing
import ZephraCore

@Suite("InferenceEnvironment reads every switch once, and forgives a typo")
struct InferenceEnvironmentTests {
    @Test("an empty environment is the defaults")
    func defaults() {
        let values = InferenceEnvironment.read([:])
        #expect(values == InferenceEnvironment())
        #expect(values.vaeTile == nil)
        #expect(values.streamDepth == 2)
        #expect(values.ditFloat32 == nil)
        #expect(values.previewInterval == PreviewThrottle.defaultInterval)
        #expect(values.weightResidency == nil)
        #expect(values.wiredLimitBytes == nil && values.memoryLimitBytes == nil && values.cacheLimitBytes == nil)
        #expect(values.videoStages == nil)
    }

    @Test("every switch is read under its documented name")
    func readsEverySwitch() {
        let values = InferenceEnvironment.read([
            "ZEPHRA_VAE_TILE": "64",
            "ZEPHRA_STREAM_DEPTH": "3",
            "ZEPHRA_DIT_DTYPE": "f32",
            "ZEPHRA_PREVIEW_INTERVAL_MS": "250",
            "ZEPHRA_WEIGHT_RESIDENCY": "streamed",
            "ZEPHRA_WIRED_LIMIT_MB": "12000",
            "ZEPHRA_MEMORY_LIMIT_MB": "30000",
            "ZEPHRA_CACHE_LIMIT_MB": "512",
            "ZEPHRA_VIDEO_STAGES": "1",
        ])
        #expect(values.vaeTile == 64)
        #expect(values.streamDepth == 3)
        #expect(values.ditFloat32 == true)
        #expect(values.previewInterval == .milliseconds(250))
        #expect(values.weightResidency == .streamed)
        #expect(values.wiredLimitBytes == 12000 * MemoryUnits.mebibyte)
        #expect(values.memoryLimitBytes == 30000 * MemoryUnits.mebibyte)
        #expect(values.cacheLimitBytes == 512 * MemoryUnits.mebibyte)
        #expect(values.videoStages == 1)
        #expect(InferenceEnvironment.read(["ZEPHRA_VIDEO_STAGES": "3"]).videoStages == nil, "only one or two")
    }

    @Test("a preview interval of zero switches frames off; a wired limit of zero is a real zero")
    func zeroMeansOffForFramesAndZeroForWiring() {
        let values = InferenceEnvironment.read([
            "ZEPHRA_PREVIEW_INTERVAL_MS": "0", "ZEPHRA_WIRED_LIMIT_MB": "0",
        ])
        #expect(values.previewInterval == nil)
        #expect(values.wiredLimitBytes == 0)
    }

    @Test("bf16 is an explicit answer, distinct from unset")
    func bf16IsExplicit() {
        #expect(InferenceEnvironment.read(["ZEPHRA_DIT_DTYPE": "bf16"]).ditFloat32 == false)
        #expect(InferenceEnvironment.read(["ZEPHRA_DIT_DTYPE": "fp16"]).ditFloat32 == nil)
    }

    @Test("a tile too small to be worth the seams, and anything unreadable, is ignored")
    func unreadableValuesAreIgnored() {
        let values = InferenceEnvironment.read([
            "ZEPHRA_VAE_TILE": "8",
            "ZEPHRA_STREAM_DEPTH": "many",
            "ZEPHRA_WEIGHT_RESIDENCY": "sometimes",
            "ZEPHRA_CACHE_LIMIT_MB": "-1",
        ])
        #expect(values == InferenceEnvironment())
    }
}
