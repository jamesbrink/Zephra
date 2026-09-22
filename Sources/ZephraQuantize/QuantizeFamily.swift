import Foundation
import ZephraBackendFlux2
import ZephraBackendLTX2
import ZephraBackendWan
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
    case flux2 = "flux2"
    case ltx2 = "ltx2"
    case ltx2Audio = "ltx2-audio"
    case wan = "wan"

    /// Every value `--family` accepts, for the usage text.
    static var names: String { allCases.map(\.rawValue).joined(separator: "|") }

    /// The directory name this family's quantized build is written to by default. It has to
    /// match the local directory the matching `ModelCatalog` entry points at.
    var defaultOutputName: String {
        switch self {
        case .zImage: "z-image-turbo-4bit"
        case .flux2: "flux2-klein-4b-4bit"
        case .ltx2: "ltx-2.5-distilled-4bit"
        case .ltx2Audio: "ltx-2.5-distilled-audio-4bit"
        case .wan: "wan-2.2-ti2v-5b-4bit"
        }
    }

    /// The repository the full-precision weights normally come from, recorded in the manifest.
    var defaultSourceName: String {
        switch self {
        case .zImage: "Tongyi-MAI/Z-Image-Turbo"
        case .flux2: "black-forest-labs/FLUX.2-klein-4B"
        case .ltx2, .ltx2Audio: "mlx-community/ltx-2.5-mlx"
        case .wan: "FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers"
        }
    }

    /// This family's packing plan at the requested precisions.
    ///
    /// FLUX.2 klein holds its three shared modulation linears whole and omits the text encoder
    /// layers past the last one the transformer reads.
    ///
    /// LTX-2.5 omits its audio stream and holds its two embeddings at eight bits.
    ///
    /// Wan 2.2 holds its conditioning and UMT5's token table at eight bits.
    func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision
    ) throws -> QuantizationPlan {
        switch self {
        case .zImage:
            return ZImageQuantizationPlan.plan(
                transformer: transformer, textEncoder: textEncoder)
        case .flux2:
            return Flux2QuantizationPlan.plan(
                transformer: transformer, textEncoder: textEncoder)
        case .ltx2, .ltx2Audio:
            return LTX2QuantizationPlan.plan(
                transformer: transformer,
                textEncoder: textEncoder,
                embeddings: transformer.bits < 8
                    ? try QuantizationPrecision(bits: 8, groupSize: transformer.groupSize)
                    : transformer,
                audio: self == .ltx2Audio
            )
        case .wan:
            return WanQuantizationPlan.plan(
                transformer: transformer,
                textEncoder: textEncoder,
                conditioning: transformer.bits < 8
                    ? try QuantizationPrecision(bits: 8, groupSize: transformer.groupSize)
                    : transformer
            )
        }
    }
}
