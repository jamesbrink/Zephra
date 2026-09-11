import Foundation
import ZephraCore
import ZephraMedia
import ZephraSnapshot

/// Drives a backend through a load, a warm-up, and a set of timed runs.
enum BenchRunner {
    /// Runs the whole benchmark and returns what it measured.
    ///
    /// The backend comes from `registry`, keyed by the descriptor, so the tool measures whichever
    /// family the chosen model belongs to and never names one itself.
    static func run(
        _ options: BenchOptions, environment: InferenceEnvironment, registry: BackendRegistry
    ) async throws -> BenchReport {
        // Either a catalogued model, or a snapshot named on the command line for a family whose
        // catalog entry does not exist yet. The flag was checked when it was parsed, so an
        // unknown identifier cannot reach here.
        // Read before anything is fetched or loaded, so an unreadable picture fails in a
        // second rather than after a sixteen-gigabyte download.
        let reference = try options.reference.map { try Data(contentsOf: $0) }
        let descriptor =
            if let snapshot = options.snapshot, let backend = options.backend {
                BenchDescriptor.forSnapshot(
                    snapshot, backend: backend, size: options.size, steps: options.steps,
                    supportsReferenceImage: reference != nil)
            } else {
                ModelCatalog.descriptor(id: options.model) ?? ModelCatalog.default
            }
        let runtime = BenchBackends.runtime(for: descriptor.backend)
        runtime.setCacheLimit(bytes: environment.cacheLimitBytes ?? cacheLimit())
        if let limit = environment.memoryLimitBytes { runtime.setMemoryLimit(bytes: limit) }
        if let limit = environment.wiredLimitBytes { runtime.setWiredLimit(bytes: limit) }
        // The tool has no settings window to choose a tile, so ZEPHRA_VAE_TILE is the tile.
        runtime.setVAETileSize(environment.vaeTile)
        let backend = try registry.make(descriptor)
        let verbose = !options.json

        // The tool has no preferences to read, so `--models` is how it is told the folder
        // Settings names; without it, models are where the app puts them by default. A
        // `--snapshot` names its own directory and is looked for there first.
        let locations = options.models.map { ModelLocations(root: $0) } ?? ModelLocations.default
        let downloaded = try await backend.ensureAvailable(descriptor, locations: locations, acquisition: ModelDownloader()) {
            event in
            note("downloading \(event.completedFiles)/\(event.totalFiles) files", verbose)
        }
        let snapshot = try await backend.build(descriptor, at: downloaded, locations: locations) {
            event in
            note("building: \(event.component) \(Int((event.fraction * 100).rounded()))%", verbose)
        }
        note("loading \(descriptor.fullName)", verbose)
        let clock = ContinuousClock()
        let residency: WeightResidency = options.stream ? .streamed : .resident
        let loadDuration = try await clock.measure {
            try await backend.load(descriptor, at: snapshot, residency: residency) { _ in }
        }

        note("warm-up", verbose)
        _ = try await backend.generate(
            warmUpSettings(descriptor, prompt: options.prompt, reference: reference)
        ) { _ in }

        // The clip's tail, read as the app reads it, held at the head of every timed run.
        var continuation: ClipContinuation?
        if let clip = options.extend {
            let context = options.context ?? descriptor.capabilities.defaultContinuationFrames
            continuation = ClipContinuation(
                frames: try await ClipTail.read(from: clip, frames: max(context, 1)),
                origin: clip.lastPathComponent, sourceFrameCount: 0)
        }
        let settings = timedSettings(
            descriptor, options: options, reference: reference, continuation: continuation)
        var runSeconds: [Double] = []
        var stepIntervals: [Double] = []
        var previewSeconds: [Double] = []
        var lastPreview: GenerationPreview?
        var firstStep = 1
        var media = GeneratedMedia.image(png: Data())
        for index in 1...options.runs {
            note("run \(index) of \(options.runs)", verbose)
            let stepClock = BenchStepClock()
            let start = clock.now
            media = try await backend.generate(settings) { event in
                stepClock.record(event)
            }
            runSeconds.append((clock.now - start).seconds)
            stepIntervals += stepClock.intervals
            previewSeconds += stepClock.previewSeconds
            lastPreview = stepClock.lastPreview ?? lastPreview
            firstStep = stepClock.firstStep ?? 1
        }
        let outputPath = try write(media, to: options.output)
        // The run joined onto the clip it carried on, the held frames dropped at the join:
        // the seam is the one part of a continuation a number cannot show.
        let extendedPath = try await BenchExtendedClip.write(
            media, onto: options.extend, dropping: settings.continuation?.contextFrames ?? 0,
            beside: options.output)
        // Written beside the image, and only when frames were asked for: a frame is the one part
        // of a run whose correctness a number cannot show.
        let previewPath = try lastPreview.map {
            try BenchPreviewImage.write($0, beside: options.output).path
        }
        let memory = runtime.memorySnapshot()
        // The last pass in the process is the last step's pass over the transformer, which is
        // the one a step time is measured against.
        let streamed = runtime.weightStreamReading()

        return BenchReport(
            device: runtime.deviceSummary(),
            model: descriptor.id,
            width: settings.size.width,
            height: settings.size.height,
            steps: settings.steps,
            // The clamped count, so a picture model reports one frame whatever `--frames` said.
            frames: settings.frames,
            firstStep: firstStep,
            // The clamped settings, not the options: a model that cannot read a picture, or
            // one that pins the strength at 1, should report what it actually ran.
            referenceStrength: settings.referenceImage == nil ? nil : settings.referenceStrength,
            loadSeconds: loadDuration.seconds,
            runSeconds: runSeconds,
            meanSecondsPerStep: mean(stepIntervals),
            previewFrames: options.preview ? previewSeconds.count : nil,
            meanPreviewSeconds: options.preview ? mean(previewSeconds) : nil,
            previewPath: previewPath,
            // What the backend says it did, not what it was asked: a family that cannot
            // stream loads resident whatever `--stream` said.
            weightResidency: backend.loadedResidency?.rawValue ?? "unknown",
            streamedGBPerStep: streamed.map { Double($0.bytes) / 1_000_000_000 },
            streamReadGBps: streamed.map { $0.bytesPerSecond / 1_000_000_000 },
            activeMemoryMB: Double(memory.activeBytes) / 1_000_000,
            cacheMemoryMB: Double(memory.cacheBytes) / 1_000_000,
            peakMemoryMB: Double(memory.peakBytes) / 1_000_000,
            outputPath: outputPath,
            referencePath: settings.referenceImage == nil ? nil : options.reference?.path,
            contextFrames: settings.continuation?.contextFrames,
            extendedPath: extendedPath,
            hasAudio: { if case .video(let video) = media { video.hasAudio } else { nil } }()
        )
    }

    /// Caps MLX's retained scratch memory, leaving room for the weights and for the rest of
    /// the machine, unless `ZEPHRA_CACHE_LIMIT_MB` said otherwise. Eight gigabytes is plenty
    /// for a 2048-pixel run.
    private static func cacheLimit() -> Int {
        let physical = Int(ProcessInfo.processInfo.physicalMemory)
        return min(8 * MemoryUnits.gibibyte, physical / 6)
    }
}
