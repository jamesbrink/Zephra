import Foundation

/// One directory of a snapshot whose linear weights get packed, and the rules deciding how.
///
/// Rules are tried in order and the first match wins, so a component reads as a short list of
/// exceptions followed by what happens to everything else. That ordering is the whole interface:
/// put the narrow rules first.
public struct QuantizedComponent: Hashable, Sendable {
    /// The subdirectory the component is written to, and where its shards are read from unless
    /// `sourceDirectory` or `sourceFiles` says otherwise.
    public let directoryName: String
    /// The release's directory for this component when it is not named `directoryName`: the
    /// LTX-2.5 pack keeps its Gemma encoder under `gemma4-12b-ltx-v1/`, which the build writes
    /// out as `text_encoder/`. Nil means the two names agree. Its configs are copied too.
    public let sourceDirectory: String?
    /// The component's shards, as paths relative to the release root, for a release that keeps
    /// them beside each other at the top rather than in a directory each; empty means "every
    /// safetensors file in the source directory".
    public let sourceFiles: [String]
    /// Exceptions, most specific first.
    public let rules: [WeightPrecisionRule]
    /// What happens to a tensor no rule claims, or nil to leave the rest of the component alone.
    public let fallback: QuantizationPrecision?
    /// Tensors left out of the build entirely.
    ///
    /// Distinct from a rule that resolves to no precision: that one copies the tensor across
    /// unpacked, which is right for a norm the model reads at full width and wrong for a
    /// component nothing ever loads. A checkpoint often carries both.
    public let omitted: [NamePattern]

    /// Creates a component whose tensors are packed at `fallback` except where `rules` say
    /// otherwise.
    public init(
        directoryName: String,
        sourceDirectory: String? = nil,
        sourceFiles: [String] = [],
        rules: [WeightPrecisionRule] = [],
        fallback: QuantizationPrecision?,
        omitted: [NamePattern] = []
    ) {
        self.directoryName = directoryName
        self.sourceDirectory = sourceDirectory
        self.sourceFiles = sourceFiles
        self.rules = rules
        self.fallback = fallback
        self.omitted = omitted
    }

    /// Where the component's shards and sidecar files are read from under `release`.
    public func sourceDirectoryURL(in release: URL) -> URL {
        release.appending(path: sourceDirectory ?? directoryName)
    }

    /// The shard files to read under `release`: the named ones, else every safetensors file in
    /// the source directory, in name order.
    public func shards(in release: URL) throws -> [URL] {
        guard sourceFiles.isEmpty else {
            return sourceFiles.map { release.appending(path: $0) }
        }
        return try FileManager.default
            .contentsOfDirectory(at: sourceDirectoryURL(in: release), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Whether this tensor is left out of the build entirely.
    public func omits(_ tensorName: String) -> Bool {
        omitted.contains { $0.matches(tensorName) }
    }

    /// How finely to pack `tensorName`, or nil to copy it across untouched.
    ///
    /// This answers only whether we *want* the tensor packed. Whether MLX *can* pack it is
    /// `QuantizableWeight`'s question, and it is asked afterwards, because the answer depends on
    /// the group size this returns.
    public func precision(for tensorName: String) -> QuantizationPrecision? {
        for rule in rules where rule.pattern.matches(tensorName) {
            return rule.precision
        }
        return fallback
    }

    /// The precisions this component can produce, for a summary line.
    var declaredPrecisions: [QuantizationPrecision] {
        (rules.compactMap(\.precision) + [fallback].compactMap { $0 })
    }
}
