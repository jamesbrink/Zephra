import Foundation
import ZephraCore

/// One generation waiting its turn behind the running one.
public struct QueuedGeneration: Identifiable, Hashable, Sendable {
    /// Stable identity, so a row in a list can be removed while the queue shifts.
    public let id: UUID
    /// The model it will run on. Queue entries can name different models; the engine swaps
    /// weights between them as it works down the queue.
    public let model: ModelDescriptor
    /// What it will render with, already clamped to `model`'s capabilities.
    public let settings: GenerationSettings

    /// Wraps a model and its settings for the queue.
    public init(model: ModelDescriptor, settings: GenerationSettings) {
        self.id = UUID()
        self.model = model
        self.settings = settings
    }
}
