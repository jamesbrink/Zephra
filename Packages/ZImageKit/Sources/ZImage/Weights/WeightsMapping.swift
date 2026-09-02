import Foundation
import Logging
import MLX
import MLXNN

public struct ZImageWeightsMapping {
  public struct Partition {
    public let transformer: [String: MLXArray]
    public let textEncoder: [String: MLXArray]
    public let vae: [String: MLXArray]
    public let unassigned: [String: MLXArray]
  }

  public static func partition(weights: [String: MLXArray], logger: Logger? = nil) -> Partition {
    var transformer: [String: MLXArray] = [:]
    var textEncoder: [String: MLXArray] = [:]
    var vae: [String: MLXArray] = [:]
    var unassigned: [String: MLXArray] = [:]

    for (key, tensor) in weights {
      if key.hasPrefix("transformer.") {
        transformer[String(key.dropFirst("transformer.".count))] = tensor
      } else if key.hasPrefix("text_encoder.") {
        textEncoder[String(key.dropFirst("text_encoder.".count))] = tensor
      } else if key.hasPrefix("vae.") {
        vae[String(key.dropFirst("vae.".count))] = tensor
      } else {
        unassigned[key] = tensor
      }
    }

    return Partition(
      transformer: transformer,
      textEncoder: textEncoder,
      vae: vae,
      unassigned: unassigned
    )
  }

  private static func transformerMapping(_ weights: [String: MLXArray]) -> [String: MLXArray] {
    var mapped: [String: MLXArray] = [:]
    for (k, v) in weights {
      mapped["transformer.\(k)"] = v
    }
    return mapped
  }

  private static func textEncoderMapping(_ weights: [String: MLXArray]) -> [String: MLXArray] {
    var mapped: [String: MLXArray] = [:]
    for (k, v) in weights {
      if k.hasPrefix("model.") {
        let remainder = String(k.dropFirst("model.".count))
        mapped["text_encoder.encoder.\(remainder)"] = v
      } else {
        mapped["text_encoder.\(k)"] = v
      }
    }
    return mapped
  }

  private static func vaeMapping(_ weights: [String: MLXArray]) -> [String: MLXArray] {
    var mapped: [String: MLXArray] = [:]
    for (k, v) in weights {
      var tensor = v
      if tensor.ndim == 4 {
        tensor = tensor.transposed(0, 2, 3, 1)
      }
      mapped["vae.\(k)"] = tensor
    }
    return mapped
  }

  public static func applyTransformer(
    weights: [String: MLXArray],
    to model: ZImageTransformer2DModel,
    manifest: ZImageQuantizationManifest? = nil,
    logger: Logger
  ) throws {
    if weights.isEmpty {
      throw WeightsApplyError.noWeights(component: "transformer")
    }

    if let manifest = manifest {
      let availableKeys = Set(weights.keys)
      ZImageQuantizer.applyQuantization(
        to: model,
        manifest: manifest,
        availableKeys: availableKeys,
        tensorNameTransform: ZImageQuantizer.transformerTensorName
      )
    }

    // ZEPHRA-PATCH: `all_final_layer.<key>.adaLN_modulation` is a module whose only child is
    // keyed "1", and `ModuleParameters.unflattened` reads a numeric path segment as an array
    // index. Feeding those keys to `Module.update` therefore offers an array where a module is
    // expected and the whole call throws, leaving the 30 transformer blocks on their random
    // initialisation whenever `items()` happens to visit the final layer first. Swift seeds
    // dictionary ordering per process, so the failure was intermittent: some runs produced a
    // real image and some produced smooth colour blobs. The final layer is loaded by
    // `loadFinalLayerWeights` just below, so withhold its keys here.
    let mapped = transformerMapping(weights).filter { !$0.key.contains(".all_final_layer.") }
    try applyToModule(model, weights: mapped, prefix: "transformer", logger: logger)

    let groupSize = manifest?.groupSize ?? 32
    let bits = manifest?.bits ?? 8
    model.loadCapEmbedderWeights(from: weights)
    model.loadXEmbedderWeights(from: weights, groupSize: groupSize, bits: bits)
    model.loadFinalLayerWeights(from: weights, groupSize: groupSize, bits: bits)

    model.setPadTokens(xPad: weights["x_pad_token"], capPad: weights["cap_pad_token"])
  }

  public static func applyTextEncoder(
    weights: [String: MLXArray],
    to model: QwenTextEncoder,
    manifest: ZImageQuantizationManifest? = nil,
    logger: Logger
  ) throws {
    if weights.isEmpty {
      throw WeightsApplyError.noWeights(component: "text_encoder")
    }

    if let manifest = manifest {
      let availableKeys = Set(weights.keys)
      ZImageQuantizer.applyQuantization(
        to: model,
        manifest: manifest,
        availableKeys: availableKeys,
        tensorNameTransform: ZImageQuantizer.textEncoderTensorName
      )
    }

    let mapped = textEncoderMapping(weights)
    try applyToModule(model, weights: mapped, prefix: "text_encoder", logger: logger)
  }

  public static func applyVAE(
    weights: [String: MLXArray],
    to model: AutoencoderKL,
    manifest: ZImageQuantizationManifest? = nil,
    logger: Logger
  ) throws {
    if weights.isEmpty {
      throw WeightsApplyError.noWeights(component: "vae")
    }

    let mapped = vaeMapping(weights)
    try applyToModule(model, weights: mapped, prefix: "vae", logger: logger)
  }

  // ZEPHRA-PATCH: a failed apply used to be logged and swallowed, which let a model with
  // randomly initialised layers report a successful load. It now throws so the caller cannot
  // miss it.
  private static func applyToModule(
    _ module: Module,
    weights: [String: MLXArray],
    prefix: String,
    logger: Logger
  ) throws {
    let params = module.parameters().flattened()
    var updates: [(String, MLXArray)] = []

    for (key, _) in params {
      let candidates = [key, "\(prefix).\(key)"]
      if let found = candidates.compactMap({ weights[$0] }).first {
        updates.append((key, found))
      }
    }

    for (weightKey, tensor) in weights {
      var paramKey = weightKey
      if weightKey.hasPrefix("\(prefix).") {
        paramKey = String(weightKey.dropFirst("\(prefix).".count))
      }

      if (paramKey.hasSuffix(".scales") || paramKey.hasSuffix(".biases")) {
        if !updates.contains(where: { $0.0 == paramKey }) {
          updates.append((paramKey, tensor))
        }
      }
    }

    if updates.isEmpty {
      throw WeightsApplyError.noMatchingWeights(component: prefix)
    }

    do {
      let nd = ModuleParameters.unflattened(updates)
      try module.update(parameters: nd, verify: [.shapeMismatch])
    } catch {
      logger.error("Failed to apply weights to \(prefix): \(error)")
      throw WeightsApplyError.applyFailed(component: prefix, reason: String(describing: error))
    }
  }
}
