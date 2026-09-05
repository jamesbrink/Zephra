import Foundation

/// Every `ZEPHRA_*` switch the inference path honours, read once from the process environment
/// at the composition root and handed down as a value.
///
/// Nothing below the root reads `ProcessInfo`: a kit takes these as arguments on its requests,
/// a backend holds them as instance state, and the benchmark overrides a field here rather than
/// setting a variable for a static somewhere to pick up. The names and meanings are the ones
/// "Debugging hooks" in AGENTS.md documents; a value that does not parse is ignored rather than
/// fatal, because a mistyped variable should not stop a generation.
public struct InferenceEnvironment: Hashable, Sendable {
    /// `ZEPHRA_VAE_TILE`: the latent tile edge to decode in, or nil for the exact decode.
    /// Anything under 16 cells is ignored as too small to be worth the seams.
    public var vaeTile: Int?
    /// `ZEPHRA_STREAM_DEPTH`: layers a streamed load reads ahead of the one running.
    public var streamDepth: Int
    /// `ZEPHRA_DIT_DTYPE`: true for `f32`, false for `bf16`, nil when unset — in which case a
    /// family's own default applies, which for klein is a device gate.
    public var ditFloat32: Bool?
    /// `ZEPHRA_PREVIEW_INTERVAL_MS`: the shortest gap between two preview frames, or nil when
    /// frames are switched off (a value of 0).
    public var previewInterval: Duration?
    /// `ZEPHRA_WEIGHT_RESIDENCY`: `streamed` or `resident`, overriding the preference for one
    /// launch; nil leaves the preference in charge.
    public var weightResidency: WeightResidency?
    /// `ZEPHRA_WIRED_LIMIT_MB`, in bytes; 0 switches wiring off.
    public var wiredLimitBytes: Int?
    /// `ZEPHRA_MEMORY_LIMIT_MB`, in bytes.
    public var memoryLimitBytes: Int?
    /// `ZEPHRA_CACHE_LIMIT_MB`, in bytes.
    public var cacheLimitBytes: Int?

    /// The values a process with nothing set runs under.
    public init(
        vaeTile: Int? = nil,
        streamDepth: Int = 2,
        ditFloat32: Bool? = nil,
        previewInterval: Duration? = PreviewThrottle.defaultInterval,
        weightResidency: WeightResidency? = nil,
        wiredLimitBytes: Int? = nil,
        memoryLimitBytes: Int? = nil,
        cacheLimitBytes: Int? = nil
    ) {
        self.vaeTile = vaeTile
        self.streamDepth = streamDepth
        self.ditFloat32 = ditFloat32
        self.previewInterval = previewInterval
        self.weightResidency = weightResidency
        self.wiredLimitBytes = wiredLimitBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.cacheLimitBytes = cacheLimitBytes
    }

    /// Reads every switch out of `environment`, which is `ProcessInfo.processInfo.environment`
    /// at the one place that is allowed to look.
    public static func read(_ environment: [String: String]) -> InferenceEnvironment {
        var values = InferenceEnvironment()
        if let tile = environment["ZEPHRA_VAE_TILE"].flatMap(Int.init), tile >= 16 {
            values.vaeTile = tile
        }
        if let depth = environment["ZEPHRA_STREAM_DEPTH"].flatMap(Int.init), depth >= 0 {
            values.streamDepth = depth
        }
        switch environment["ZEPHRA_DIT_DTYPE"] {
        case "f32": values.ditFloat32 = true
        case "bf16": values.ditFloat32 = false
        default: break
        }
        if let milliseconds = environment["ZEPHRA_PREVIEW_INTERVAL_MS"].flatMap(Int.init) {
            values.previewInterval = milliseconds > 0 ? .milliseconds(milliseconds) : nil
        }
        values.weightResidency = environment["ZEPHRA_WEIGHT_RESIDENCY"]
            .flatMap(WeightResidency.init(rawValue:))
        values.wiredLimitBytes = bytes(environment["ZEPHRA_WIRED_LIMIT_MB"])
        values.memoryLimitBytes = bytes(environment["ZEPHRA_MEMORY_LIMIT_MB"])
        values.cacheLimitBytes = bytes(environment["ZEPHRA_CACHE_LIMIT_MB"])
        return values
    }

    /// A limit written in megabytes, as bytes, or nil when it is unset or unreadable.
    private static func bytes(_ megabytes: String?) -> Int? {
        guard let value = megabytes.flatMap(Int.init), value >= 0 else { return nil }
        return value * MemoryUnits.mebibyte
    }
}
