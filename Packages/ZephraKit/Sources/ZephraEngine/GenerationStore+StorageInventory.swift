import Foundation

extension GenerationStore {
    public var modelStorageRoot: URL { locations.root }
    public func storageInventory() -> ModelInventory { ModelInventory(locations: locations) }
}
