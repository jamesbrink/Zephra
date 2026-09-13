import Foundation
import Logging
import MLX
// ZEPHRA-PATCH: `ShardIndex`, so a stream can be told where a component's tensors are.
import ZephraMLX


public struct ZImageWeightsMapper {
  private let snapshot: URL
  private let logger: Logger

  public init(snapshot: URL, logger: Logger) {
    self.snapshot = snapshot
    self.logger = logger
  }

  public func hasQuantization() -> Bool {
    ZImageQuantizer.hasQuantization(at: snapshot)
  }

  public func loadQuantizationManifest() -> ZImageQuantizationManifest? {
    let manifestURL = snapshot.appendingPathComponent("quantization.json")
    return try? ZImageQuantizationManifest.load(from: manifestURL)
  }


  public func loadAll(dtype: DType? = .bfloat16) throws -> [String: MLXArray] {
    if hasQuantization() {
      logger.info("Detected quantized model, loading from quantized safetensors")
      return try loadQuantizedAll()
    }
    return try loadStandardAll(dtype: dtype)
  }

  public func loadTextEncoder(dtype: DType? = .bfloat16) throws -> [String: MLXArray] {
    if hasQuantization() {
      return try loadQuantizedComponent("text_encoder")
    }
    return try loadStandardComponent(files: ZImageFiles.textEncoderWeights, dtype: dtype)
  }

  public func loadTransformer(dtype: DType? = .bfloat16) throws -> [String: MLXArray] {
    if hasQuantization() {
      return try loadQuantizedComponent("transformer")
    }
    return try loadStandardComponent(files: ZImageFiles.transformerWeights, dtype: dtype)
  }

  public func loadVAE(dtype: DType? = .bfloat16) throws -> [String: MLXArray] {
    if hasQuantization() {
      return try loadQuantizedComponent("vae")
    }
    return try loadStandardComponent(files: ZImageFiles.vaeWeights, dtype: dtype)
  }

  /// Load controlnet weights from a standalone safetensors file
  public func loadControlnetWeights(from path: String, dtype: DType? = .bfloat16) throws -> [String: MLXArray] {
    let url: URL
    if path.hasPrefix("/") {
      url = URL(fileURLWithPath: path)
    } else {
      url = snapshot.appending(path: path)
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      throw NSError(domain: "ZImageWeightsMapper", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Controlnet weights file not found: \(url.path)"
      ])
    }

    var tensors: [String: MLXArray] = [:]
    let reader = try SafeTensorsReader(fileURL: url)
    for meta in reader.allMetadata() {
      var tensor = try reader.tensor(named: meta.name)
      if let targetDtype = dtype, tensor.dtype != targetDtype {
        tensor = tensor.asType(targetDtype)
      }
      tensors[meta.name] = tensor
    }

    logger.info("Loaded \(tensors.count) controlnet tensors from \(url.lastPathComponent)")
    return tensors
  }

  private func loadStandardComponent(files: [String], dtype: DType?) throws -> [String: MLXArray] {
    var tensors: [String: MLXArray] = [:]
    for relative in files {
      let url = snapshot.appending(path: relative)
      guard FileManager.default.fileExists(atPath: url.path) else {
        logger.warning("Weight shard missing: \(relative)")
        continue
      }
      let reader = try SafeTensorsReader(fileURL: url)
      for meta in reader.allMetadata() {
        var tensor = try reader.tensor(named: meta.name)
        if let targetDtype = dtype, tensor.dtype != targetDtype {
          tensor = tensor.asType(targetDtype)
        }
        tensors[meta.name] = tensor
      }
    }
    return tensors
  }

  private func loadQuantizedComponent(_ componentName: String) throws -> [String: MLXArray] {
    let fm = FileManager.default
    let resolvedSnapshot = snapshot.resolvingSymlinksInPath()
    var tensors: [String: MLXArray] = [:]

    let componentDir = resolvedSnapshot.appendingPathComponent(componentName)
    guard fm.fileExists(atPath: componentDir.path) else {
      logger.warning("Component directory not found: \(componentName)")
      return tensors
    }

    let contents = try fm.contentsOfDirectory(at: componentDir, includingPropertiesForKeys: nil)
    // ZEPHRA-PATCH: sorted by name, first one wins. `contentsOfDirectory` has no defined order
    // and the loop below used to let the last shard read win, so which tensor a duplicated key
    // resolved to was the file system's choice. This is `ShardIndex`'s rule and
    // `SafetensorsShards.weights`', so a stream and this loader cannot disagree about which
    // shard a tensor came from. No catalog snapshot carries a key in two shards, so nothing
    // that loads today changes.
    let safetensorFiles = contents
      .filter { $0.pathExtension == "safetensors" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    for file in safetensorFiles {
      let weights = try MLX.loadArrays(url: file)
      for (key, value) in weights where tensors[key] == nil {  // ZEPHRA-PATCH: first wins
        tensors[key] = value
      }
    }
    return tensors
  }

  // ZEPHRA-PATCH: where a component's tensors live and what they cost to read, without reading
  // any of them, so `LayerWeightStream` can open a pass over the same shards this loader reads.
  // `ShardIndex(directory:)` sorts by name and takes the first of a duplicated key, which is
  // exactly what `loadQuantizedComponent` above now does.
  /// Indexes the shards of `component` — `transformer`, `text_encoder` or `vae` — in the
  /// resolved snapshot, for a stream to read them from.
  public func shardIndex(for component: String) throws -> ShardIndex {
    try ShardIndex(
      directory: snapshot.resolvingSymlinksInPath().appendingPathComponent(component))
  }

  private func loadStandardAll(dtype: DType?) throws -> [String: MLXArray] {
    var tensors: [String: MLXArray] = [:]

    for (key, value) in try loadStandardComponent(files: ZImageFiles.transformerWeights, dtype: dtype) {
      tensors["transformer.\(key)"] = value
    }
    for (key, value) in try loadStandardComponent(files: ZImageFiles.textEncoderWeights, dtype: dtype) {
      tensors["text_encoder.\(key)"] = value
    }
    for (key, value) in try loadStandardComponent(files: ZImageFiles.vaeWeights, dtype: dtype) {
      tensors["vae.\(key)"] = value
    }

    if let targetDtype = dtype {
      logger.info("Converted weights to \(targetDtype)")
    }
    logger.info("Aggregated \(tensors.count) tensors from safetensors shards")
    return tensors
  }

  private func loadQuantizedAll() throws -> [String: MLXArray] {
    var tensors: [String: MLXArray] = [:]

    for (key, value) in try loadQuantizedComponent("transformer") {
      tensors["transformer.\(key)"] = value
    }
    for (key, value) in try loadQuantizedComponent("text_encoder") {
      tensors["text_encoder.\(key)"] = value
    }
    for (key, value) in try loadQuantizedComponent("vae") {
      tensors["vae.\(key)"] = value
    }

    logger.info("Aggregated \(tensors.count) tensors from quantized safetensors")
    return tensors
  }
}
