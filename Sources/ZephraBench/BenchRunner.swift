import Foundation
import ZephraCore
import ZephraSnapshot

/// Drives a backend through a load, a warm-up, and a set of timed runs.
enum BenchRunner {
    /// Runs the whole benchmark and returns what it measured.
    ///
    /// The backend comes from `registry`, keyed by the descriptor, so the tool measures whichever
    /// family the chosen model belongs to and never names one itself.
    static func run(_ options: BenchOptions, registry: BackendRegistry) async throws -> BenchReport {
        BenchBackends.runtime().setCacheLimit(bytes: cacheLimit())
        // The backends read this when they build their throttle, so it has to be set before the
        // first generation and not after. Zero switches the frames off, which is the default
        // here: a benchmark measures the model, unless it was asked to measure the frames too.
        setenv("ZEPHRA_PREVIEW_INTERVAL_MS", options.preview ? "750" : "0", 1)
        if let depth = options.streamDepth {
            setenv("ZEPHRA_STREAM_DEPTH", String(depth), 1)
        }
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
        let backend = try registry.make(descriptor)
        let verbose = !options.json

        // The tool has no preferences to read, so models are where the app puts them by
        // default; a `--snapshot` names its own directory and is looked for there first.
        let locations = ModelLocations.default
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

        let settings = timedSettings(descriptor, options: options, reference: reference)
        var runSeconds: [Double] = []
        var stepIntervals: [Double] = []
        var previewSeconds: [Double] = []
        var lastPreview: GenerationPreview?
        var firstStep = 1
        var image = Data()
        for index in 1...options.runs {
            note("run \(index) of \(options.runs)", verbose)
            let stepClock = BenchStepClock()
            let start = clock.now
            image = try await backend.generate(settings) { event in
                stepClock.record(event)
            }
            runSeconds.append((clock.now - start).seconds)
            stepIntervals += stepClock.intervals
            previewSeconds += stepClock.previewSeconds
            lastPreview = stepClock.lastPreview ?? lastPreview
            firstStep = stepClock.firstStep ?? 1
        }
        try write(image, to: options.output)
        // Written beside the image, and only when frames were asked for: a frame is the one part
        // of a run whose correctness a number cannot show.
        let previewPath = try lastPreview.map {
            try BenchPreviewImage.write($0, beside: options.output).path
        }
        let memory = BenchBackends.runtime().memorySnapshot()
        // The last pass in the process is the last step's pass over the transformer, which is
        // the one a step time is measured against.
        let streamed = BenchBackends.runtime().weightStreamReading()

        return BenchReport(
            device: BenchBackends.runtime().deviceSummary(),
            model: descriptor.id,
            size: settings.size.width,
            steps: settings.steps,
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
            weightResidency: residency.rawValue,
            streamedGBPerStep: streamed.map { Double($0.bytes) / 1_000_000_000 },
            streamReadGBps: streamed.map { $0.bytesPerSecond / 1_000_000_000 },
            activeMemoryMB: Double(memory.activeBytes) / 1_000_000,
            cacheMemoryMB: Double(memory.cacheBytes) / 1_000_000,
            peakMemoryMB: Double(memory.peakBytes) / 1_000_000,
            outputPath: options.output.path,
            referencePath: settings.referenceImage == nil ? nil : options.reference?.path
        )
    }

    /// A cheap, tiny generation that pays the one-off costs, so the timed runs measure steady
    /// state rather than Metal kernel compilation and first-touch page faults.
    ///
    /// The reference goes into the warm-up too: an edit runs a longer sequence through
    /// different kernel shapes, and warming up without it would leave the first timed run to
    /// pay for their compilation, which is the thing the warm-up exists to prevent.
    private static func warmUpSettings(
        _ descriptor: ModelDescriptor,
        prompt: String,
        reference: Data?
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = prompt
        settings.size = ImageSize(width: 512, height: 512)
        settings.steps = 1
        settings.seed = 1
        settings.referenceImage = reference
        return descriptor.capabilities.clamp(settings)
    }

    /// The settings every timed run shares. The seed is fixed so repeated invocations produce
    /// the same image and the same amount of work. The result is put through the model's own
    /// limits here rather than only inside the backend, so the report states the size and step
    /// count that actually ran instead of the ones that were asked for — and, on a model that
    /// cannot start from a picture, says so by leaving `--reference` out of the report.
    private static func timedSettings(
        _ descriptor: ModelDescriptor,
        options: BenchOptions,
        reference: Data?
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = options.prompt
        settings.size = ImageSize(width: options.size, height: options.size)
        settings.steps = options.steps
        settings.seed = 42
        settings.referenceImage = reference
        settings.referenceStrength = options.referenceStrength
        return descriptor.capabilities.clamp(settings)
    }

    /// Caps MLX's retained scratch memory, leaving room for the weights and for the rest of
    /// the machine. Eight gigabytes is plenty for a 2048-pixel run.
    private static func cacheLimit() -> Int {
        if let override = ProcessInfo.processInfo.environment["ZEPHRA_CACHE_LIMIT_MB"],
           let megabytes = Int(override) {
            return megabytes * 1_000_000
        }
        let physical = Int(ProcessInfo.processInfo.physicalMemory)
        return min(8_000_000_000, physical / 6)
    }

    private static func write(_ image: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.write(to: url)
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func note(_ message: String, _ verbose: Bool) {
        guard verbose else { return }
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
