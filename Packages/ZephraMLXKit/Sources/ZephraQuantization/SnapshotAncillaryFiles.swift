import Foundation

/// Copies everything a snapshot needs besides the weights that were packed: the top-level
/// config, the per-component configs, and every directory the plan leaves at full precision.
///
/// Copies go through `FileManager`, which moves the bytes without reading a file into memory,
/// so an unquantized VAE's couple of hundred megabytes never land in the process.
public enum SnapshotAncillaryFiles {
    /// Mirrors the non-weight parts of `source` into `destination`, following `plan`.
    public static func copy(from source: URL, to destination: URL, plan: QuantizationPlan) throws {
        // Keyed by the directory the release keeps a component in, which is where its configs
        // are; they land in the directory the plan writes the component to.
        let packed = Dictionary(
            uniqueKeysWithValues: plan.components.map { ($0.sourceDirectory ?? $0.directoryName, $0) })
        for entry in try contents(of: source) {
            let name = entry.lastPathComponent
            if entry.hasDirectoryPath {
                if plan.verbatimDirectories.contains(name) {
                    try copyItem(at: entry, to: destination.appending(path: name))
                } else if let component = packed[name] {
                    try copyConfigs(named: component.directoryName, from: entry, to: destination)
                }
            } else if name != "quantization.json", entry.pathExtension != "safetensors" {
                try copyItem(at: entry, to: destination.appending(path: name))
            }
        }
    }

    /// Copies a packed component's sidecar files, which is everything but its shards and the
    /// safetensors index describing a layout they no longer have.
    private static func copyConfigs(named name: String, from directory: URL, to destination: URL)
        throws
    {
        let outputDirectory = destination.appending(path: name)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        for entry in try contents(of: directory) {
            let entryName = entry.lastPathComponent
            guard !entry.hasDirectoryPath,
                entry.pathExtension != "safetensors",
                !entryName.hasSuffix(".safetensors.index.json")
            else { continue }
            try copyItem(at: entry, to: outputDirectory.appending(path: entryName))
        }
    }

    private static func contents(of directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies one file or directory, replacing whatever is already there.
    ///
    /// Directories are walked rather than handed to `copyItem` wholesale, and every file is
    /// resolved before it is copied: a Hugging Face snapshot is a tree of relative symlinks into
    /// the blob store, and copying those as links would leave the new snapshot pointing at
    /// nothing.
    private static func copyItem(at source: URL, to destination: URL) throws {
        let files = FileManager.default
        guard source.hasDirectoryPath else {
            if files.fileExists(atPath: destination.path(percentEncoded: false)) {
                try files.removeItem(at: destination)
            }
            try files.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
            return
        }
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try contents(of: source) {
            try copyItem(at: entry, to: destination.appending(path: entry.lastPathComponent))
        }
    }
}
