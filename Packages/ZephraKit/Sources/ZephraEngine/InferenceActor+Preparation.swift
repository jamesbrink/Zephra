import Foundation
import ZephraCore
import ZephraSnapshot

extension InferenceActor {
    /// Fetches the weights if they are missing, packs them if the family loads something other
    /// than its download, then reads them into memory, reporting every stage through `events`,
    /// and returns the directory the weights were read from. Doing nothing, and handing back
    /// the same directory, is the right answer if the model is already loaded the way
    /// `residency` asks for.
    @discardableResult
    func prepare(
        _ descriptor: ModelDescriptor,
        residency: WeightResidency = .resident,
        events: EngineEventSink
    ) async throws -> URL {
        let live = try backend(for: descriptor)
        if live.loadedModelID == descriptor.id, loadedResidency == residency, let loadedPath {
            return loadedPath
        }
        // Read once: a folder changed during the download must not have the build looking
        // for what was fetched, or writing, under a root the download never used.
        let locations = self.locations
        let downloaded = try await live.ensureAvailable(descriptor, locations: locations,
            acquisition: ModelDownloader()) { events.send(.download($0)) }
        return try await prepare(
            AcquiredModel(id: UUID(), model: descriptor, locations: locations, directory: downloaded),
            residency: residency, events: events)
    }

    /// Acquisition is independent; only one settled foreground operation enters this lane.
    func prepare(
        _ acquired: AcquiredModel,
        residency: WeightResidency = .resident,
        events: EngineEventSink
    ) async throws -> URL {
        do {
            // The boundary covers the build and the load alike: a pack reads and writes tensors
            // on the device, and a fault in either is the same lost operation.
            return try await catchingDeviceErrors { () async throws -> URL in
                try Task.checkCancellation()
                let live = try self.backend(for: acquired.model)
                // Already up the way `residency` asks: the same shortcut the descriptor overload
                // takes, so no path through here reads the weights a second time.
                if live.loadedModelID == acquired.model.id, self.loadedResidency == residency,
                    let loadedPath = self.loadedPath
                {
                    return loadedPath
                }
                let localPath: URL
                if acquired.installedOnly { localPath = acquired.directory }
                else {
                    localPath = try await live.build(acquired.model, at: acquired.directory,
                        locations: acquired.locations) { events.send(.build($0)) }
                }
                try Task.checkCancellation()
                try await live.load(acquired.model, at: localPath, residency: residency) {
                    events.send(.progress($0))
                }
                try Task.checkCancellation()
                self.loadedPath = localPath
                self.loadedResidency = residency
                return localPath
            }
        } catch {
            unload()
            throw error
        }
    }

    /// Runs one tiny generation and throws the result away, so the first image the user asks
    /// for is not the one that pays for kernel compilation. `tile` is the VAE tile it decodes
    /// at, set on this queue the way `generate` sets it.
    func warmUp(_ descriptor: ModelDescriptor, tile: Int?) async throws {
        let live = try backend(for: descriptor)
        runtime?.setVAETileSize(tile)
        let settings = descriptor.capabilities.clamp(
            GenerationSettings(
                prompt: Self.warmUpPrompt,
                size: Self.warmUpSize,
                steps: 1,
                guidance: descriptor.capabilities.defaultGuidance,
                seed: 0
            )
        )
        try Task.checkCancellation()
        _ = try await catchingDeviceErrors {
            try await live.generate(settings) { _ in }
        }
        try Task.checkCancellation()
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
