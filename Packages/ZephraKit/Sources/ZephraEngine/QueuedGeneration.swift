import Foundation
import ZephraCore

/// One generation waiting its turn behind the running one.
public struct QueuedGeneration: Identifiable, Hashable, Sendable {
    public let requiresInstalledModel: Bool

    /// Stable identity, so a row in a list can be removed while the queue shifts.
    public let id: UUID
    /// The model it will run on. Queue entries can name different models; the engine swaps
    /// weights between them as it works down the queue.
    public let model: ModelDescriptor
    /// What it will render with, already clamped to `model`'s capabilities.
    public let settings: GenerationSettings
    /// Which press of Generate produced it. Several seeds of one prompt share this, which is
    /// what lets the interface show "this run" without guessing where a run started.
    public let batchID: UUID
    /// Where in that run it comes, counting from zero.
    public let batchIndex: Int
    /// Which pass of a chained clip this is, when the clip is longer than one pass; nil for a
    /// clip made in one. Every pass but the last carries on into the next rather than being
    /// published; see `GenerationStore+Chaining.swift`.
    public let chain: ChainSegment?

    /// Wraps a model and its settings for the queue. Left to itself it is a run of one.
    public init(
        model: ModelDescriptor,
        settings: GenerationSettings,
        batchID: UUID = UUID(),
        batchIndex: Int = 0,
        chain: ChainSegment? = nil,
        requiresInstalledModel: Bool = false
    ) {
        self.requiresInstalledModel = requiresInstalledModel
        self.id = UUID()
        self.model = model
        self.settings = settings
        self.batchID = batchID
        self.batchIndex = batchIndex
        self.chain = chain
    }
}
