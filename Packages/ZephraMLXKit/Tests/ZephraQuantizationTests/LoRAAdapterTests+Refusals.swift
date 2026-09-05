import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import ZephraQuantization

/// The adapter files this reader turns away, rather than reading as an adapter of nothing.
extension LoRAAdapterTests {
    @Test("an adapter whose tensors follow no known naming is refused, not merged as nothing")
    func refusesAFileThatNamesNoFactor() throws {
        let scratch = Scratch("LoRAAdapter")
        // A spelling this reader does not know: parsed, every tensor is skipped, and the
        // adapter that came back used to be empty, merge nothing, and hand back the base
        // model as if it had been distilled.
        let url = try Self.write(
            [
                "lora_unet_blocks_0_to_q.down": MLXArray.ones([2, 3]),
                "lora_unet_blocks_0_to_q.up": MLXArray.ones([4, 2]),
            ],
            to: scratch.url("unknown-naming.safetensors")
        )
        #expect(throws: QuantizationError.adapterNamesNothing(url)) {
            _ = try LoRAAdapter(contentsOf: [url])
        }
    }

    @Test("a file that names nothing is refused even beside one that does")
    func refusesTheEmptyFileInAStack() throws {
        let scratch = Scratch("LoRAAdapter")
        let good = try Self.write(Self.pair(), to: scratch.url("adapter.safetensors"))
        let empty = try Self.write(
            ["blocks.0.to_q.something_else": MLXArray.ones([2, 3])],
            to: scratch.url("empty.safetensors"))
        #expect(throws: QuantizationError.adapterNamesNothing(empty)) {
            _ = try LoRAAdapter(contentsOf: [good, empty])
        }
    }

    @Test("the refusal says which file, and that kohya exports are not read")
    func theRefusalNamesTheFile() {
        let description = QuantizationError.adapterNamesNothing(
            URL(filePath: "/adapters/lightning.safetensors")
        ).errorDescription ?? ""
        #expect(description.contains("lightning.safetensors"))
        #expect(description.contains("lora_unet_"))
    }
}
