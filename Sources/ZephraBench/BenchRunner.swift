import Foundation
import ZephraBackendZImage
import ZephraCore

/// Drives a backend through a load, a warm-up, and a set of timed runs.
enum BenchRunner {
    /// Runs the whole benchmark and returns what it measured.
    ///
    /// The backend comes from `registry`, keyed by the descriptor, so the tool measures whichever
    /// family the chosen model belongs to and never names one itself.
    static func run(_ options: BenchOptions, registry: BackendRegistry) async throws -> BenchReport {
        ZImageRuntime.configure(cacheLimitBytes: cacheLimit(), memoryLimitBytes: nil)
        // Checked when the flag was parsed, so an unknown identifier cannot reach here.
        let descriptor = ModelCatalog.descriptor(id: options.model) ?? ModelCatalog.default
        let backend = try registry.make(descriptor)
        let verbose = !options.json

        let snapshot = try await backend.ensureAvailable(descriptor) { event in
            note("downloading \(event.completedFiles)/\(event.totalFiles) files", verbose)
        }
        note("loading \(descriptor.fullName)", verbose)
        let clock = ContinuousClock()
        let loadDuration = try await clock.measure {
            try await backend.load(descriptor, at: snapshot) { _ in }
        }

        note("warm-up", verbose)
        _ = try await backend.generate(warmUpSettings(descriptor, prompt: options.prompt)) { _ in }

        let settings = timedSettings(descriptor, options: options)
        var runSeconds: [Double] = []
        var stepIntervals: [Double] = []
        var image = Data()
        for index in 1...options.runs {
            note("run \(index) of \(options.runs)", verbose)
            let stepClock = BenchStepClock()
            let start = clock.now
            image = try await backend.generate(settings) { event in
                stepClock.record(event.phase)
            }
            runSeconds.append((clock.now - start).seconds)
            stepIntervals += stepClock.intervals
        }
        try write(image, to: options.output)
        let memory = ZImageRuntime.memorySnapshot()

        return BenchReport(
            device: ZImageRuntime.deviceSummary(),
            model: descriptor.id,
            size: settings.size.width,
            steps: settings.steps,
            loadSeconds: loadDuration.seconds,
            runSeconds: runSeconds,
            meanSecondsPerStep: mean(stepIntervals),
            activeMemoryMB: Double(memory.active) / 1_000_000,
            peakMemoryMB: Double(memory.peak) / 1_000_000,
            outputPath: options.output.path
        )
    }

    /// A cheap, tiny generation that pays the one-off costs, so the timed runs measure steady
    /// state rather than Metal kernel compilation and first-touch page faults.
    private static func warmUpSettings(
        _ descriptor: ModelDescriptor,
        prompt: String
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = prompt
        settings.size = ImageSize(width: 512, height: 512)
        settings.steps = 1
        settings.seed = 1
        return settings
    }

    /// The settings every timed run shares. The seed is fixed so repeated invocations produce
    /// the same image and the same amount of work. The result is put through the model's own
    /// limits here rather than only inside the backend, so the report states the size and step
    /// count that actually ran instead of the ones that were asked for.
    private static func timedSettings(
        _ descriptor: ModelDescriptor,
        options: BenchOptions
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = options.prompt
        settings.size = ImageSize(width: options.size, height: options.size)
        settings.steps = options.steps
        settings.seed = 42
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
