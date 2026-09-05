import Foundation
import Logging
import MLX
import MLXNN
import MLXRandom
import Tokenizers
import Hub
import Dispatch

// ZEPHRA-PATCH: SDEdit takes its reference picture as a CGImage.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct ZImageGenerationRequest: Sendable {
  public var prompt: String
  public var negativePrompt: String?
  public var width: Int
  public var height: Int
  public var steps: Int
  public var guidanceScale: Float
  public var seed: UInt64?
  public var outputPath: URL
  public var model: String?
  public var maxSequenceLength: Int

  public var lora: LoRAConfiguration?

  public var enhancePrompt: Bool

  public var enhanceMaxTokens: Int

  // ZEPHRA-PATCH: SDEdit. A picture the generation starts from instead of pure noise, and how
  // far it may travel from it: 1 ignores the picture entirely and is the ordinary
  // text-to-image path, smaller values keep more of it. Both default to the old behaviour, so
  // every existing caller is unchanged.
  #if canImport(CoreGraphics)
  public var referenceImage: CGImage? = nil
  #endif
  public var referenceStrength: Float

  public init(
    prompt: String,
    negativePrompt: String? = nil,
    width: Int = ZImageModelMetadata.recommendedWidth,
    height: Int = ZImageModelMetadata.recommendedHeight,
    steps: Int = ZImageModelMetadata.recommendedInferenceSteps,
    guidanceScale: Float = ZImageModelMetadata.recommendedGuidanceScale,
    seed: UInt64? = nil,
    outputPath: URL = URL(fileURLWithPath: "z-image.png"),
    model: String? = nil,
    maxSequenceLength: Int = 512,
    lora: LoRAConfiguration? = nil,
    enhancePrompt: Bool = false,
    enhanceMaxTokens: Int = 512,
    // ZEPHRA-PATCH: SDEdit, defaulted so this stays source-compatible.
    referenceStrength: Float = 1.0
  ) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.width = width
    self.height = height
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.seed = seed
    self.outputPath = outputPath
    self.model = model
    self.maxSequenceLength = maxSequenceLength
    self.lora = lora
    self.enhancePrompt = enhancePrompt
    self.enhanceMaxTokens = enhanceMaxTokens
    self.referenceStrength = referenceStrength  // ZEPHRA-PATCH: SDEdit
  }
}

public final class ZImagePipeline {
  public enum PipelineError: Error, Sendable {
    case notImplemented
    case tokenizerNotLoaded
    case invalidDimensions(String)
    case textEncoderNotLoaded
    case transformerNotLoaded
    case vaeNotLoaded
    case weightsMissing(String)
    case modelNotLoaded
    case loraError(LoRAError)
  }

  private var logger: Logger
  private let hubApi: HubApi
  private var tokenizer: QwenTokenizer?
  private var textEncoder: QwenTextEncoder?
  private var transformer: ZImageTransformer2DModel?
  private var vae: AutoencoderKL?
  private var modelConfigs: ZImageModelConfigs?
  private var quantManifest: ZImageQuantizationManifest?
  private var isModelLoaded: Bool = false
  private var loadedModelId: String?
  private var currentLoRA: LoRAWeights?
  private var currentLoRAConfig: LoRAConfiguration?
  private var modelSnapshot: URL?
  private var useDynamicLoRA: Bool = false

  // ZEPHRA-PATCH: returning MLX's scratch to the system after every generation trades the next
  // generation's warm buffers for a smaller footprint. It is worth it here because the VAE
  // decode's peak is what pushes this process into memory pressure, but it is a knob.
  /// Whether to hand MLX's cached scratch memory back after each generation.
  public var clearsCacheAfterGeneration =
    ProcessInfo.processInfo.environment["ZEPHRA_KEEP_CACHE"] != "1"

  public init(logger: Logger = Logger(label: "z-image.pipeline"), hubApi: HubApi = .shared) {
    self.logger = logger
    self.hubApi = hubApi
  }
  public var isLoaded: Bool {
    return isModelLoaded
  }
  public func unloadModel() {
    tokenizer = nil
    textEncoder = nil
    transformer = nil
    vae = nil
    modelConfigs = nil
    quantManifest = nil
    isModelLoaded = false
    loadedModelId = nil

    currentLoRA = nil
    currentLoRAConfig = nil
    modelSnapshot = nil
    useDynamicLoRA = false
    GPU.clearCache()
    logger.info("Model unloaded from memory")
  }

  public func unloadLoRA() {
    guard currentLoRA != nil else { return }

    if let trans = transformer {

      LoRAApplicator.clearDynamicLoRA(from: trans, logger: logger)
    }
    currentLoRA = nil
    currentLoRAConfig = nil
    useDynamicLoRA = false
    GPU.clearCache()
    logger.info("LoRA unloaded (instant)")
  }
  public func unloadTransformer() {
    transformer = nil

    currentLoRA = nil
    currentLoRAConfig = nil
    useDynamicLoRA = false

    GPU.clearCache()
    logger.info("Transformer unloaded for memory optimization")
  }

  private func getAvailableMemory() -> UInt64 {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let pageSize = UInt64(sysconf(_SC_PAGESIZE))
    return UInt64(stats.free_count) * pageSize
  }

  private func loadTokenizer(snapshot: URL) throws -> QwenTokenizer {
    let tokDir = snapshot.appending(path: "tokenizer")
    return try QwenTokenizer.load(from: tokDir, hubApi: hubApi)
  }

  private func loadTextEncoder(snapshot: URL, config: ZImageTextEncoderConfig) throws -> QwenTextEncoder {
    return QwenTextEncoder(
      configuration: .init(
        vocabSize: config.vocabSize,
        hiddenSize: config.hiddenSize,
        numHiddenLayers: config.numHiddenLayers,
        numAttentionHeads: config.numAttentionHeads,
        numKeyValueHeads: config.numKeyValueHeads,
        intermediateSize: config.intermediateSize,
        ropeTheta: config.ropeTheta,
        maxPositionEmbeddings: config.maxPositionEmbeddings,
        rmsNormEps: config.rmsNormEps,
        headDim: config.headDim
      )
    )
  }

  private func loadTransformer(snapshot: URL, config: ZImageTransformerConfig) throws -> ZImageTransformer2DModel {
    return ZImageTransformer2DModel(configuration: config)
  }

  private func loadVAE(snapshot: URL, config: ZImageVAEConfig) throws -> AutoencoderKL {
    return AutoencoderKL(configuration: .init(
      inChannels: config.inChannels,
      outChannels: config.outChannels,
      latentChannels: config.latentChannels,
      scalingFactor: config.scalingFactor,
      shiftFactor: config.shiftFactor,
      blockOutChannels: config.blockOutChannels,
      layersPerBlock: config.layersPerBlock,
      normNumGroups: config.normNumGroups,
      sampleSize: config.sampleSize,
      midBlockAddAttention: config.midBlockAddAttention
    ))
  }

  private func encodePrompt(_ prompt: String, tokenizer: QwenTokenizer, textEncoder: QwenTextEncoder, maxLength: Int) throws -> (MLXArray, MLXArray) {
    do {
      let result = try PipelineUtilities.encodePrompt(prompt, tokenizer: tokenizer, textEncoder: textEncoder, maxLength: maxLength)
      return (result.embeddings, result.mask)
    } catch {
      throw PipelineError.textEncoderNotLoaded
    }
  }
  public struct GenerationProgress: Sendable {
    public let stage: Stage
    public let stepIndex: Int
    public let totalSteps: Int

    public enum Stage: String, Sendable {
      case loadingModel = "Loading model"
      case encodingText = "Encoding text"
      case loadingTransformer = "Loading transformer"
      case loadingLoRA = "Loading LoRA"
      case denoising = "Denoising"
      case loadingVAE = "Loading VAE"
      case decoding = "Decoding"
      case saving = "Saving"
    }

    public var fractionCompleted: Double {
      guard totalSteps > 0 else { return 0 }
      return Double(stepIndex) / Double(totalSteps)
    }

    public var percentComplete: Int {
      Int(fractionCompleted * 100)
    }
  }

  public typealias ProgressHandler = (GenerationProgress) -> Void

  // ZEPHRA-PATCH: a second, optional hook for a host that shows a run as it happens.
  /// Called after a denoising step has been evaluated, with the step it just finished
  /// (counting from zero), how many there are, and a way to decode the latent as it stands.
  ///
  /// The frame is a closure rather than a value because making one is a pass through the
  /// autoencoder: a host that shows frames only every so often never pays for the ones it would
  /// have thrown away. How often that is belongs to the host, not to this package.
  public typealias PreviewHandler = (
    _ step: Int, _ totalSteps: Int, _ frame: () -> ZImageLatentPreview
  ) -> Void
  public func loadModel(modelSpec: String? = nil, progressHandler: ProgressHandler? = nil) async throws {
    let modelId = modelSpec ?? ZImageRepository.id
    if isModelLoaded && loadedModelId == modelId {
      logger.info("Model already loaded, skipping load")
      return
    }
    let canPreserveSharedComponents = isModelLoaded
      && loadedModelId != modelId
      && areZImageVariants(loadedModelId ?? "", modelId)
    if isModelLoaded && loadedModelId != modelId {
      if canPreserveSharedComponents {
        logger.info("Switching Z-Image variant, preserving VAE and tokenizer")

        textEncoder = nil
        transformer = nil

        currentLoRA = nil
        currentLoRAConfig = nil
        useDynamicLoRA = false
      } else {
        logger.info("Different model requested, unloading current model")
        unloadModel()
      }
    }

    logger.info("Loading model: \(modelId)")
    progressHandler?(GenerationProgress(stage: .loadingModel, stepIndex: 0, totalSteps: 1))

    let snapshot = try await PipelineSnapshot.prepare(model: modelSpec, logger: logger)
    let configs = try ZImageModelConfigs.load(from: snapshot)
    let weightsMapper = ZImageWeightsMapper(snapshot: snapshot, logger: logger)
    let manifest = weightsMapper.loadQuantizationManifest()

    if let m = manifest {
      logger.info("Loading quantized model (bits=\(m.bits), group_size=\(m.groupSize))")
    }
    if tokenizer == nil {
      progressHandler?(GenerationProgress(stage: .encodingText, stepIndex: 0, totalSteps: 1))
      logger.info("Loading tokenizer...")
      tokenizer = try loadTokenizer(snapshot: snapshot)
    } else {
      logger.info("Reusing cached tokenizer")
    }
    // ZEPHRA-PATCH: the `noteMemory` lines through this function are ZEPHRA_PROFILE_STEP's
    // memory readings; see `ZImageStepProfile`.
    ZImageStepProfile.noteMemory("mem: before text enc")
    logger.info("Loading text encoder...")
    let te = try loadTextEncoder(snapshot: snapshot, config: configs.textEncoder)
    let textEncoderWeights = try weightsMapper.loadTextEncoder()
    try ZImageWeightsMapping.applyTextEncoder(weights: textEncoderWeights, to: te, manifest: manifest, logger: logger)  // ZEPHRA-PATCH: a failed apply throws
    textEncoder = te
    progressHandler?(GenerationProgress(stage: .loadingTransformer, stepIndex: 0, totalSteps: 1))
    ZImageStepProfile.noteMemory("mem: before dit")
    logger.info("Loading transformer...")
    let trans = try loadTransformer(snapshot: snapshot, config: configs.transformer)
    ZImageStepProfile.noteMemory("mem: dit constructed")
    let transformerWeights = try weightsMapper.loadTransformer()
    ZImageStepProfile.noteMemory("mem: dit file read")
    try ZImageWeightsMapping.applyTransformer(weights: transformerWeights, to: trans, manifest: manifest, logger: logger)  // ZEPHRA-PATCH: a failed apply throws
    // ZEPHRA-PATCH: the 8-bit repository stores scales, norms and the unquantized projections
    // as F32, which dragged every layer into float32 arithmetic. Move them to the DiT's own
    // precision once, at load, rather than casting on every step.
    ZImageStepProfile.noteMemory("mem: dit applied")
    trans.castFloatParameters(to: ZImageTransformerPrecision.activation)
    transformer = trans
    if vae == nil {
      progressHandler?(GenerationProgress(stage: .loadingVAE, stepIndex: 0, totalSteps: 1))
      logger.info("Loading VAE...")
      let v = try loadVAE(snapshot: snapshot, config: configs.vae)
      let vaeWeights = try weightsMapper.loadVAE()
      try ZImageWeightsMapping.applyVAE(weights: vaeWeights, to: v, manifest: manifest, logger: logger)  // ZEPHRA-PATCH: a failed apply throws
      vae = v
    } else {
      logger.info("Reusing cached VAE")
    }

    ZImageStepProfile.noteMemory("mem: load done")
    modelConfigs = configs
    quantManifest = manifest
    modelSnapshot = snapshot
    isModelLoaded = true
    loadedModelId = modelId

    logger.info("Model loaded successfully and cached in memory")
  }
  public func loadLoRA(_ config: LoRAConfiguration, progressHandler: ProgressHandler? = nil) async throws {
    guard let trans = transformer else {
      throw PipelineError.transformerNotLoaded
    }
    if let currentConfig = currentLoRAConfig, currentConfig == config {
      logger.info("LoRA already loaded with same configuration, skipping")
      return
    }
    if currentLoRA != nil {
      logger.info("Unloading previous LoRA...")
      unloadLoRA()
    }

    progressHandler?(GenerationProgress(stage: .loadingLoRA, stepIndex: 0, totalSteps: 1))
    logger.info("Loading LoRA from \(config.source.displayName)...")

    do {

      let loraWeights = try await LoRAWeightLoader.load(from: config)
      logger.info("Loaded LoRA: rank=\(loraWeights.rank), alpha=\(loraWeights.alpha), layers=\(loraWeights.layerCount)")

      useDynamicLoRA = true
      LoRAApplicator.applyDynamically(to: trans, loraWeights: loraWeights, scale: config.scale, logger: logger)

      currentLoRA = loraWeights
      currentLoRAConfig = config

      logger.info("LoRA applied successfully with scale=\(config.scale)")
    } catch let error as LoRAError {
      throw PipelineError.loraError(error)
    }
  }
  public var hasLoRALoaded: Bool {
    return currentLoRA != nil
  }
  public var loadedLoRAConfig: LoRAConfiguration? {
    return currentLoRAConfig
  }

  public func generate(_ request: ZImageGenerationRequest, progressHandler: ProgressHandler? = nil) async throws -> URL {
    logger.info("Requested Z-Image generation")

    let decoded = try await generateCore(request, progressHandler: progressHandler)

    progressHandler?(GenerationProgress(stage: .saving, stepIndex: request.steps, totalSteps: request.steps))
    try QwenImageIO.saveImage(array: decoded, to: request.outputPath)
    logger.info("Wrote image to \(request.outputPath.path)")

    return request.outputPath
  }
  // ZEPHRA-PATCH: `previewHandler` added, defaulted so every existing caller is unchanged.
  public func generateToMemory(_ request: ZImageGenerationRequest, progressHandler: ProgressHandler? = nil, previewHandler: PreviewHandler? = nil) async throws -> Data {
    logger.info("Requested Z-Image generation (to memory)")

    let decoded = try await generateCore(request, progressHandler: progressHandler, previewHandler: previewHandler)

    progressHandler?(GenerationProgress(stage: .saving, stepIndex: request.steps, totalSteps: request.steps))
    let imageData = try QwenImageIO.imageData(from: decoded)
    logger.info("Generated image data (\(imageData.count) bytes)")

    return imageData
  }
  // ZEPHRA-PATCH: `previewHandler` threaded through from `generateToMemory`.
  private func generateCore(_ request: ZImageGenerationRequest, progressHandler: ProgressHandler? = nil, previewHandler: PreviewHandler? = nil) async throws -> MLXArray {

    let vaeScale = 16
    if request.width % vaeScale != 0 {
      throw PipelineError.invalidDimensions("Width must be divisible by \(vaeScale) (got \(request.width)). Please adjust to a multiple of \(vaeScale).")
    }
    if request.height % vaeScale != 0 {
      throw PipelineError.invalidDimensions("Height must be divisible by \(vaeScale) (got \(request.height)). Please adjust to a multiple of \(vaeScale).")
    }
    let requestedModelId = request.model ?? ZImageRepository.id
    if !isModelLoaded || loadedModelId != requestedModelId {
      try await loadModel(modelSpec: request.model, progressHandler: progressHandler)
    }

    guard let tokenizer = tokenizer,
          let textEncoder = textEncoder,
          let transformer = transformer,
          let vae = vae,
          let modelConfigs = modelConfigs else {
      throw PipelineError.modelNotLoaded
    }
    if let loraConfig = request.lora {

      if currentLoRAConfig != loraConfig {
        try await loadLoRA(loraConfig, progressHandler: progressHandler)
      }
    } else if currentLoRA != nil {

      unloadLoRA()
    }
    progressHandler?(GenerationProgress(stage: .encodingText, stepIndex: 0, totalSteps: request.steps))
    var finalPrompt = request.prompt
    if request.enhancePrompt {
      logger.info("Enhancing prompt using LLM (max tokens: \(request.enhanceMaxTokens))...")
      let enhanceConfig = PromptEnhanceConfig(
        maxNewTokens: request.enhanceMaxTokens,
        temperature: 0.7,
        topP: 0.9,
        repetitionPenalty: 1.05
      )
      let enhanced = try textEncoder.enhancePrompt(request.prompt, tokenizer: tokenizer, config: enhanceConfig)
      if enhanced.isEmpty {
        logger.warning("Prompt enhancement incomplete (need more tokens), using original prompt")
      } else {
        logger.info("Enhanced prompt: \(enhanced)")
        finalPrompt = enhanced
      }
      if clearsCacheAfterGeneration { GPU.clearCache() }  // ZEPHRA-PATCH: the cache knob
    }
    logger.info("Encoding prompts...")

    let promptEmbeds: MLXArray
    let negativeEmbeds: MLXArray?
    let doCFG = request.guidanceScale > 1.0

    // ZEPHRA-PATCH: time the text encoder under ZEPHRA_PROFILE_STEP.
    let (pe, _) = try ZImageStepProfile.measure("text encode") {
      let encoded = try encodePrompt(finalPrompt, tokenizer: tokenizer, textEncoder: textEncoder, maxLength: request.maxSequenceLength)
      // ZEPHRA-PATCH: text encoding is lazy, so without this its cost would be billed to the
      // first denoise step instead of to itself.
      if ZImageStepProfile.isEnabled { MLX.eval(encoded.0) }
      return encoded
    }
    promptEmbeds = pe

    if doCFG {
      let (ne, _) = try encodePrompt(request.negativePrompt ?? "", tokenizer: tokenizer, textEncoder: textEncoder, maxLength: request.maxSequenceLength)
      negativeEmbeds = ne
      MLX.eval(promptEmbeds, ne)
    } else {
      negativeEmbeds = nil
      MLX.eval(promptEmbeds)
    }
    logger.info("Text encoding complete")

    let vaeDivisor = modelConfigs.vae.latentDivisor
    let latentH = max(1, request.height / vaeDivisor)
    let latentW = max(1, request.width / vaeDivisor)
    let shape: [Int] = [1, ZImageModelMetadata.Transformer.inChannels, latentH, latentW]
    // ZEPHRA-PATCH: mlx-swift 0.31 cannot pass `any RandomStateOrKey` generically; use the concrete key type.
    let randomKey: MLXArray? = request.seed.map { MLXRandom.key($0) }
    var latents = MLXRandom.normal(shape, loc: 0, scale: 1, key: randomKey)

    let mu = calculateShift(
      imageSeqLen: latentH * latentW,
      baseSeqLen: modelConfigs.scheduler.baseImageSeqLen ?? 256,
      maxSeqLen: modelConfigs.scheduler.maxImageSeqLen ?? 4096,
      baseShift: modelConfigs.scheduler.baseShift ?? 0.5,
      maxShift: modelConfigs.scheduler.maxShift ?? 1.15
    )

    let scheduler = FlowMatchEulerScheduler(
      numInferenceSteps: request.steps,
      config: modelConfigs.scheduler,
      mu: modelConfigs.scheduler.useDynamicShifting ? mu : nil
    )

    let timestepsArray = scheduler.timesteps.asArray(Float.self)

    // ZEPHRA-PATCH: SDEdit. With a reference picture the loop does not start from pure noise at
    // the top of the ladder: strength buys a share of the steps, so it enters that many from
    // the end, from that picture's latent carrying that step's share of the run's own seeded
    // noise. Without one, `startIndex` is 0 and `latents` is untouched, which is the unpatched
    // behaviour exactly.
    var startIndex = 0
    #if canImport(CoreGraphics)
    if let reference = request.referenceImage {
      // The encode is a whole pass through the autoencoder, so a run cancelled while the model
      // was still loading should stop here rather than at the first step.
      try Task.checkCancellation()
      let sigmasArray = scheduler.sigmas.asArray(Float.self)
      startIndex = ReferenceLatents.startIndex(
        strength: request.referenceStrength, steps: request.steps
      )
      let referenceLatents = try ZImageStepProfile.measure("reference encode") { () -> MLXArray in
        let encoded = try PipelineUtilities.encodeImageToLatents(
          cgImage: reference,
          vae: vae,
          latentChannels: vae.configuration.latentChannels,
          shiftFactor: vae.configuration.shiftFactor,
          scalingFactor: vae.configuration.scalingFactor,
          pixelH: latentH * vaeDivisor,
          pixelW: latentW * vaeDivisor
        )
        MLX.eval(encoded)
        return encoded
      }
      latents = ReferenceLatents.mixed(
        reference: referenceLatents, noise: latents, sigma: sigmasArray[startIndex]
      )
      MLX.eval(latents)
      logger.info(
        "Reference at strength \(request.referenceStrength): entering at step \(startIndex) of \(request.steps)"
      )
    }
    #endif

    logger.info("Running \(request.steps - startIndex) of \(request.steps) denoising steps...")
    // ZEPHRA-PATCH: the range starts at `startIndex`, and the progress reports keep counting
    // against the full `request.steps`, so a caller drawing one segment per step sees the
    // skipped ones as already finished rather than seeing a shorter run.
    for stepIndex in startIndex..<request.steps {
      try Task.checkCancellation()
      progressHandler?(GenerationProgress(stage: .denoising, stepIndex: stepIndex, totalSteps: request.steps))
      let timestep = timestepsArray[stepIndex]
      let normalizedTimestep = (1000.0 - timestep) / 1000.0
      let timestepArray = MLXArray([normalizedTimestep], [1])

      var modelLatents = latents
      var embeds = promptEmbeds
      if doCFG, let ne = negativeEmbeds {
        modelLatents = MLX.concatenated([latents, latents], axis: 0)
        embeds = MLX.concatenated([promptEmbeds, ne], axis: 0)
      }

      // ZEPHRA-PATCH: split the step into graph construction and kernel execution when
      // ZEPHRA_PROFILE_STEP=1; `measure` calls straight through otherwise.
      let noisePred = ZImageStepProfile.measure("step build") {
        transformer.forward(latents: modelLatents, timestep: timestepArray, promptEmbeds: embeds)
      }
      var guidedNoise: MLXArray
      if doCFG, negativeEmbeds != nil {
        let batch = latents.dim(0)
        let positive = noisePred[0 ..< batch, 0..., 0..., 0...]
        let negative = noisePred[batch ..< batch * 2, 0..., 0..., 0...]
        // ZEPHRA-PATCH: Swift 6.3 misresolves `Float * MLXArray` here; make the scalar an MLXArray.
        guidedNoise = positive + MLXArray(request.guidanceScale) * (positive - negative)
      } else {
        guidedNoise = noisePred
      }

      guidedNoise = -guidedNoise
      latents = scheduler.step(modelOutput: guidedNoise, timestepIndex: stepIndex, sample: latents)
      ZImageStepProfile.measure("step eval") { MLX.eval(latents) }
      // ZEPHRA-PATCH: a frame of the run, after the evaluation so it shows the step that has
      // just finished, and never on the last step: the real decode follows it immediately, and
      // a pooled one in front of that is a second pass through the autoencoder for a picture
      // the caller is a moment from seeing properly.
      //
      // What is decoded is the run's estimate of the *finished* latent, not the latent it is
      // holding. One more Euler step of this prediction, all the way to zero noise, is
      // `x - sigma * v`, and that is what a person means by "how is it coming along"; the
      // latent itself is still part noise and decodes to mush on the early rungs.
      if let previewHandler, stepIndex < request.steps - 1 {
        let target = latents
        let velocity = guidedNoise
        let sigmaNext = scheduler.sigmas[stepIndex + 1].asType(latents.dtype)
        previewHandler(stepIndex, request.steps) {
          ZImageStepProfile.measure("preview decode") {
            ZImageLatentPreview.make(latents: target - velocity * sigmaNext, vae: vae)
          }
        }
      }
    }

    ZImageStepProfile.noteMemory("mem: denoise done")
    logger.info("Denoising complete, decoding with VAE...")
    progressHandler?(GenerationProgress(stage: .decoding, stepIndex: request.steps, totalSteps: request.steps))

    // ZEPHRA-PATCH: the decode is forced inside the timed block under ZEPHRA_PROFILE_STEP so
    // its cost lands on the VAE line rather than on whatever later touches the array.
    let decoded = try ZImageStepProfile.measure("vae decode") { () throws -> MLXArray in  // ZEPHRA-PATCH: stop between VAE tiles
      let image = try decodeLatents(latents, vae: vae, height: request.height, width: request.width)  // ZEPHRA-PATCH: stop between VAE tiles
      if ZImageStepProfile.isEnabled { MLX.eval(image) }
      return image
    }
    ZImageStepProfile.noteMemory("mem: decode done")
    MLX.eval(MLXArray([]))
    if clearsCacheAfterGeneration { GPU.clearCache() }  // ZEPHRA-PATCH: the cache knob

    return decoded
  }

  private func decodeLatents(_ latents: MLXArray, vae: AutoencoderKL, height: Int, width: Int) throws -> MLXArray {  // ZEPHRA-PATCH: stop between VAE tiles
    try PipelineUtilities.decodeLatents(latents, vae: vae, height: height, width: width)  // ZEPHRA-PATCH: stop between VAE tiles
  }

  private func calculateShift(
    imageSeqLen: Int,
    baseSeqLen: Int,
    maxSeqLen: Int,
    baseShift: Float,
    maxShift: Float
  ) -> Float {
    PipelineUtilities.calculateShift(
      imageSeqLen: imageSeqLen,
      baseSeqLen: baseSeqLen,
      maxSeqLen: maxSeqLen,
      baseShift: baseShift,
      maxShift: maxShift
    )
  }

  private func areZImageVariants(_ model1: String, _ model2: String) -> Bool {
    let zImageIds: Set<String> = [
      "Tongyi-MAI/Z-Image-Turbo",
      "mzbac/Z-Image-Turbo-8bit"
    ]
    return zImageIds.contains(model1) && zImageIds.contains(model2)
  }

}
