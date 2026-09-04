import Foundation
import ZephraCore

/// An explicit move of catalog-owned model folders from one root to another.
public struct ModelMigration: Sendable {
    public let source: URL
    public let destination: URL
    let catalog: [ModelDescriptor]

    public init(from source: URL, to destination: URL, catalog: [ModelDescriptor] = ModelCatalog.all) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
        self.catalog = catalog
    }

    /// Relative directories only; never the image library, hub cache, or unrelated files.
    func directories() throws -> [String] {
        let files = FileManager.default
        let from = source.resolvingSymlinksInPath().path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let to = destination.resolvingSymlinksInPath().path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !from.isEmpty, !to.isEmpty, from != to, !from.hasPrefix(to + "/"), !to.hasPrefix(from + "/") else {
            throw ModelDirectoryError("Choose separate model folders; neither can be inside the other.")
        }
        guard files.fileExists(atPath: source.path) else { return [] }
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw ModelDirectoryError("The source models folder cannot be a symbolic link.")
        }
        var paths: Set<String> = []
        for model in catalog {
            guard case .huggingFace(let repo, _, _) = model.source else { continue }
            paths.insert("Downloads/" + repo.replacingOccurrences(of: "/", with: "--"))
            for adapter in model.adapters {
                paths.insert("Downloads/" + adapter.repoID.replacingOccurrences(of: "/", with: "--"))
            }
            if model.isBuiltLocally {
                paths.insert(model.id)
                paths.insert(model.id + ".partial")
            }
        }
        return try paths.sorted().filter { path in
            let origin = source.appending(path: path)
            guard files.fileExists(atPath: origin.path) else { return false }
            guard origin.resolvingSymlinksInPath().path.hasPrefix(source.resolvingSymlinksInPath().path + "/") else {
                throw ModelDirectoryError("Cannot move a model through a symbolic link: \(origin.path).")
            }
            let target = destination.appending(path: path)
            // Check every existing destination component, including dangling links.
            var component = target
            while component.path.count >= destination.path.count {
                if ((try? files.attributesOfItem(atPath: component.path))?[.type] as? FileAttributeType) == .typeSymbolicLink {
                    throw ModelDirectoryError("The destination contains a symbolic link: \(component.path).")
                }
                component.deleteLastPathComponent()
            }
            guard !files.fileExists(atPath: target.path) else {
                throw ModelDirectoryError("A model already exists at \(target.path). Both copies were kept. Choose an empty folder to move these models.")
            }
            return true
        }
    }
}
