import Foundation
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

    /// Every value `--family` accepts, for the usage text.
    static var names: String { allCases.map(\.rawValue).joined(separator: "|") }

    /// The directory name this family's quantized build is written to by default. It has to
    /// match the local directory the matching `ModelCatalog` entry points at.
    var defaultOutputName: String {
        switch self {
        case .zImage: "z-image-turbo-4bit"
        case .qwenImage: "qwen-image-2512-4bit"
        }
    }

    /// The repository the full-precision weights normally come from, recorded in the manifest.
    var defaultSourceName: String {
        switch self {
        case .zImage: "Tongyi-MAI/Z-Image-Turbo"
        case .qwenImage: "Qwen/Qwen-Image-2512"
        }
    }

    /// This family's packing plan at the requested precisions.
    ///
    /// Qwen-Image holds its modulation layers at eight bits whatever the rest is set to: they
    /// are a third of its parameters and they decide how strongly every other layer responds.
    ///
    /// `adapters` are merged into whichever component the family adapts, which for both families
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
        }
    }
}
