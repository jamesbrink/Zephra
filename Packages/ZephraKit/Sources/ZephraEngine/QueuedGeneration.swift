import Foundation
import ZephraCore

/// One generation waiting its turn behind the running one.
public struct QueuedGeneration: Identifiable, Hashable, Sendable {
    /// Stable identity, so a row in a list can be removed while the queue shifts.
    public let id: UUID
    /// What it will render with, already clamped to the model's capabilities.
    public let settings: GenerationSettings

    /// Wraps settings for the queue.
    public init(settings: GenerationSettings) {
        self.id = UUID()
        self.settings = settings
    }
}
