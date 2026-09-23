import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

@Suite("The prefix cache gives a later step the same answer as a whole one")
struct KVCacheTests {
    @Test("one block extracts its prefix and then decodes from it")
    func blockExtractThenCached() throws {
        let fixture = try Fixture.load("transformer_block")
        let block = try Self.block(fixture)
        let cache = QwenImage21KVLayerCache()
        let mask = MLXArray(try Fixture.flags(fixture, "in.targetTokenMask"))
        let prefix = try TransformerParityTests.prefixLength(fixture)
        let rotary = try TransformerParityTests.rotary(fixture)
        let hidden = try #require(fixture["in.hidden"])

        let prefill = try block(
            hidden,
            modulation: QwenImage21SharedModulation.split(
                try #require(fixture["in.modulationFirst"]), targetTokenMask: mask),
            frequencies: rotary,
            plan: QwenImage21AttentionPlan.prefill(
                segments: try TransformerParityTests.segments(fixture),
                keyValid: nil,
                sequenceLength: mask.dim(0)),
            cache: cache,
            mode: .extract,
            prefixLength: prefix)
        #expect(
            Fixture.maxAbsoluteDifference(prefill, try #require(fixture["out.prefill"])) < 1e-4)

        // The cache holds the prefix head-major, which is the reference's
        // `[batch, tokens, heads, headDim]` with the two middle axes swapped.
        let held = try cache.read()
        let reference = try #require(fixture["cache.key"]).transposed(0, 2, 1, 3)
        #expect(held.key.shape == reference.shape)
        #expect(Fixture.maxAbsoluteDifference(held.key, reference) < 1e-4)

        let cached = try block(
            hidden[0..., prefix...],
            modulation: QwenImage21SharedModulation.split(
                try #require(fixture["in.modulationSecond"]),
                targetTokenMask: mask[prefix...]),
            frequencies: RotaryFrequencies(
                cos: rotary.cos[prefix...], sin: rotary.sin[prefix...]),
            plan: QwenImage21AttentionPlan.decode(
                targetTokens: mask.dim(0) - prefix, keyValid: nil),
            cache: cache,
            mode: .cached,
            prefixLength: prefix)
        let expected = try #require(fixture["out.cached"])
        #expect(cached.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(cached, expected) < 1e-4)

        // The point of the whole thing: the cached step's target tokens are what a fresh pass
        // over the whole sequence at the same timestep would have produced. The reference notes
        // the two are not bit-identical in reduced precision; the doll's house runs in float32,
        // where they are.
        #expect(
            Fixture.maxAbsoluteDifference(cached, try #require(fixture["out.fresh"])) < 1e-4)
    }

    @Test("a whole model's second step reads the cache and matches an uncached one")
    func wholeModelDecodesFromTheCache() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try TransformerFixture.model(fixture)
        let layout = try TransformerFixture.layout(
            "cached", in: fixture, shapes: "oneReference")
        let frequencies = try TransformerFixture.frequencies(layout)
        let cache = QwenImage21KVCache(layers: model.layerCount)
        let latents = try #require(fixture["cached.in.hidden"])
        let text = try #require(fixture["cached.in.encoder"])

        _ = try model(
            latents: latents, text: text,
            timestep: try #require(fixture["cached.in.first"]),
            layout: layout, frequencies: frequencies, cache: cache, mode: .extract)
        let cached = try model(
            latents: latents, text: text,
            timestep: try #require(fixture["cached.in.second"]),
            layout: layout, frequencies: frequencies, cache: cache, mode: .cached)

        let expected = try #require(fixture["cached.out.velocity"])
        #expect(cached.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(cached, expected) < 1e-4)
        #expect(
            Fixture.maxAbsoluteDifference(cached, try #require(fixture["cached.out.fresh"]))
                < 1e-4)
    }

    @Test("classifier-free guidance keeps two caches that do not see each other")
    func twoCaches() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try TransformerFixture.model(fixture)
        let layout = try TransformerFixture.layout(
            "cached", in: fixture, shapes: "oneReference")
        let frequencies = try TransformerFixture.frequencies(layout)
        let latents = try #require(fixture["cached.in.hidden"])
        let text = try #require(fixture["cached.in.encoder"])
        let first = try #require(fixture["cached.in.first"])
        let second = try #require(fixture["cached.in.second"])

        // One cache is filled from this prompt, the other from a different one. A cache that
        // leaked into its neighbour would give the two the same answer.
        let positive = QwenImage21KVCache(layers: model.layerCount)
        let negative = QwenImage21KVCache(layers: model.layerCount)
        let other = text * MLXArray(Float(-1))
        _ = try model(
            latents: latents, text: text, timestep: first, layout: layout,
            frequencies: frequencies, cache: positive, mode: .extract)
        _ = try model(
            latents: latents, text: other, timestep: first, layout: layout,
            frequencies: frequencies, cache: negative, mode: .extract)

        let conditioned = try model(
            latents: latents, text: text, timestep: second, layout: layout,
            frequencies: frequencies, cache: positive, mode: .cached)
        let unconditioned = try model(
            latents: latents, text: other, timestep: second, layout: layout,
            frequencies: frequencies, cache: negative, mode: .cached)

        #expect(
            Fixture.maxAbsoluteDifference(conditioned, try #require(fixture["cached.out.velocity"]))
                < 1e-4)
        #expect(Fixture.maxAbsoluteDifference(conditioned, unconditioned) > 1e-3)
    }

    @Test("a step that reads a cache the first step never filled is refused")
    func unfilledCache() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try TransformerFixture.model(fixture)
        let layout = try TransformerFixture.layout(
            "cached", in: fixture, shapes: "oneReference")
        #expect(throws: QwenImage21TransformerError.cacheWasNotExtracted) {
            _ = try model(
                latents: try #require(fixture["cached.in.hidden"]),
                text: try #require(fixture["cached.in.encoder"]),
                timestep: try #require(fixture["cached.in.second"]),
                layout: layout,
                frequencies: try TransformerFixture.frequencies(layout),
                cache: QwenImage21KVCache(layers: model.layerCount),
                mode: .cached)
        }
    }

    static func block(_ fixture: [String: MLXArray]) throws -> QwenImage21TransformerBlock {
        let configuration = try TransformerFixture.configuration()
        let block = QwenImage21TransformerBlock(
            dim: configuration.innerDim,
            heads: configuration.numAttentionHeads,
            headDim: configuration.attentionHeadDim,
            mlpHidden: configuration.mlpHiddenSize,
            eps: configuration.eps)
        try PackedWeightLoading.load(
            into: block,
            weights: QwenImage21TransformerWeights.sanitized(
                Fixture.weights(fixture, under: "block.")),
            manifest: nil)
        return block
    }
}
