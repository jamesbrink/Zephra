import Foundation
import ZephraBackendFlux2
import ZephraBackendLTX2
import ZephraBackendQwenImage
import ZephraBackendZImage
import ZephraCore
import ZephraQuantization

/// The model families this tool can build a quantized snapshot for.
///
/// One case per family, and the switch below is the only place the tool names a plan. It is a
/// switch rather than a registry because `ModelCatalog` is the only static registry this
/// codebase keeps, and because two arms are easier to read than a registration dance.
enum QuantizeFamily: String, CaseIterable, Sendable {
    case zImage = "z-image"
    case qwenImage = "qwen-image"
    case flux2 = "flux2"
    case ltx2 = "ltx2"

    /// Every value `--family` accepts, for the usage text.
    static var names: String { allCases.map(\.rawValue).joined(separator: "|") }

    /// The directory name this family's quantized build is written to by default. It has to
    /// match the local directory the matching `ModelCatalog` entry points at.
    var defaultOutputName: String {
        switch self {
        case .zImage: "z-image-turbo-4bit"
        case .qwenImage: "qwen-image-2512-4bit"
        case .flux2: "flux2-klein-4b-4bit"
        case .ltx2: "ltx-2.5-distilled-4bit"
        }
    }

    /// The repository the full-precision weights normally come from, recorded in the manifest.
    var defaultSourceName: String {
        switch self {
        case .zImage: "Tongyi-MAI/Z-Image-Turbo"
        case .qwenImage: "Qwen/Qwen-Image-2512"
        case .flux2: "black-forest-labs/FLUX.2-klein-4B"
        case .ltx2: "mlx-community/ltx-2.5-mlx"
        }
    }

    /// Whether the catalog's build of this family is the release with an adapter merged in.
    ///
    /// Qwen-Image's four-step distillation ships as an adapter, and the catalog entry — no
    /// guidance, no negative prompt — describes the merged weights. A build without it loads
    /// under that entry and runs, and makes soft, hazy pictures; so the tool refuses to make
    /// one unless told to with `--no-lora`.
    var requiresAdapter: Bool { self == .qwenImage }

    /// This family's packing plan at the requested precisions.
    ///
    /// Qwen-Image holds its modulation layers at eight bits whatever the rest is set to: they
    /// are a third of its parameters and they decide how strongly every other layer responds.
    ///
    /// FLUX.2 klein holds its three shared modulation linears whole and omits the text encoder
    /// layers past the last one the transformer reads.
    ///
    /// LTX-2.5 omits its audio stream and holds its two embeddings at eight bits; it merges no
    /// adapter, so `adapters` is refused rather than silently dropped.
    ///
    /// `adapters` are merged into whichever component the family adapts, which for every family
    /// here is the diffusion transformer.
    func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        adapters: [URL]
    ) throws -> QuantizationPlan {
        switch self {
        case .zImage:
            ZImageQuantizationPlan.plan(
                transformer: transformer, textEncoder: textEncoder, adapters: adapters)
        case .qwenImage:
            QwenImageQuantizationPlan.plan(
                transformer: transformer,
                textEncoder: textEncoder,
                modulation: transformer.bits < 8
                    ? try QuantizationPrecision(bits: 8, groupSize: transformer.groupSize)
                    : transformer,
                adapters: adapters
            )
        case .flux2:
            Flux2QuantizationPlan.plan(
                transformer: transformer, textEncoder: textEncoder, adapters: adapters)
        case .ltx2:
            if !adapters.isEmpty {
                throw QuantizeUsageError.adapterNotRead(family: rawValue)
            }
            return LTX2QuantizationPlan.plan(
                transformer: transformer,
                textEncoder: textEncoder,
                embeddings: transformer.bits < 8
                    ? try QuantizationPrecision(bits: 8, groupSize: transformer.groupSize)
                    : transformer
            )
        }
    }
}
