import Foundation
import ZephraCore
import ZephraSnapshot

extension InferenceActor {
    /// Fetches the weights if they are missing, packs them if the family loads something other
    /// than its download, then reads them into memory, reporting every stage through `events`,
    /// and returns the directory the weights were read from. Doing nothing, and handing back
    /// the same directory, is the right answer if the model is already loaded.
    @discardableResult
    func prepare(_ descriptor: ModelDescriptor, events: EngineEventSink) async throws -> URL {
        let live = try backend(for: descriptor)
        if live.loadedModelID == descriptor.id, let loadedPath { return loadedPath }
        // Read once: a folder changed during the download must not have the build looking
        // for what was fetched, or writing, under a root the download never used.
        let locations = self.locations
        let downloaded = try await live.ensureAvailable(descriptor, locations: locations,
            acquisition: ModelDownloader()) { events.send(.download($0)) }
        return try await prepare(AcquiredModel(id: UUID(), model: descriptor,
            locations: locations, directory: downloaded), events: events)
    }

    /// Acquisition is independent; only one settled foreground operation enters this lane.
    func prepare(_ acquired: AcquiredModel, events: EngineEventSink) async throws -> URL {
        do {
            try Task.checkCancellation()
            let live = try backend(for: acquired.model)
            let localPath = try await live.build(acquired.model, at: acquired.directory,
                locations: acquired.locations) { events.send(.build($0)) }
            try Task.checkCancellation()
            try await live.load(acquired.model, at: localPath) { events.send(.progress($0)) }
            try Task.checkCancellation()
            loadedPath = localPath
            return localPath
        } catch {
            unload()
            throw error
        }
    }

    /// Whether `descriptor`'s weights are already on this Mac. Never downloads, and never
    /// disturbs what is loaded: a backend built only to answer this is thrown away afterwards.
    func availability(of descriptor: ModelDescriptor) async -> ModelAvailability {
        guard let probe = try? registry.make(descriptor) else {
            return .missing(reason: "No engine in this build can run \(descriptor.backend.rawValue) models.")
        }
        return await probe.availability(of: descriptor, locations: locations)
    }

}
