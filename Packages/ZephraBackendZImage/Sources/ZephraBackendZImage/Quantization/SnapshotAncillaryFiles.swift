import Foundation

/// Copies everything a snapshot needs besides the weights themselves: `model_index.json`, the
/// per-component configs, the tokenizer, the scheduler, and the VAE, which stays unquantized.
///
/// Copies go through `FileManager`, which moves the bytes without reading a file into memory,
/// so the VAE's two hundred megabytes never land in the process.
enum SnapshotAncillaryFiles {
    /// Directories copied whole, weights and all.
    private static let verbatimDirectories = ["tokenizer", "scheduler", "vae"]

    /// Mirrors the non-weight parts of `source` into `destination`.
    static func copy(from source: URL, to destination: URL) throws {
        for entry in try contents(of: source) {
            let name = entry.lastPathComponent
            if entry.hasDirectoryPath {
                if verbatimDirectories.contains(name) {
                    try copyItem(at: entry, to: destination.appending(path: name))
                } else if let component = QuantizedComponent(rawValue: name) {
                    try copyConfigs(of: component, from: entry, to: destination)
                }
            } else if name != "quantization.json", entry.pathExtension != "safetensors" {
                try copyItem(at: entry, to: destination.appending(path: name))
            }
        }
    }

    /// Copies a quantized component's sidecar files, which is everything but its shards and the
    /// safetensors index that describes the layout they no longer have.
    private static func copyConfigs(
        of component: QuantizedComponent,
        from directory: URL,
        to destination: URL
    ) throws {
        let outputDirectory = destination.appending(path: component.directoryName)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        for entry in try contents(of: directory) {
            let name = entry.lastPathComponent
            guard !entry.hasDirectoryPath,
                entry.pathExtension != "safetensors",
                !name.hasSuffix(".safetensors.index.json")
            else { continue }
            try copyItem(at: entry, to: outputDirectory.appending(path: name))
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
