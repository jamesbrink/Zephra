import Foundation
import ZephraCore

/// A press of Generate, asked for from the phone.
///
/// The settings are `ZephraCore`'s own, so the Mac clamps what arrives with the same `clamp`
/// every local press goes through and no second set of rules exists. The one thing stripped is
/// the pixels (`GenerationSettings.withoutPixels`): megabytes of PNG inside a JSON envelope
/// would block the channel for everything else, so a picture crosses as a blob and is named
/// here by its id.
///
/// It also carries the phone's own `requestID`, which is the one thing in the protocol that
/// makes a repeat safe. Every other command says what the Mac should end up like; this one adds
/// work, so a request sent again after its `queued` reply went missing would queue the run
/// twice. The Mac remembers the run each id made for the life of the session and answers the
/// same `queued(batchID)` instead.
public struct GenerationRequest: Hashable, Sendable {
    /// The most seeds one press may ask for, which is the Mac's own batch limit.
    public static let countBounds = 1...8

    /// The phone's own name for this press of Generate, made once and kept across a retry: the
    /// envelope's id changes when a request is asked again, and this does not.
    public var requestID: UUID
    /// The model to run it on, as a descriptor identifier.
    public var modelID: String
    /// How many seeds to queue, clamped to `countBounds`.
    public var count: Int
    /// Everything else the user chose. Its `referenceImage` is always nil here.
    public private(set) var settings: GenerationSettings
    /// The blob already sent that holds the reference picture, or nil for a run from nothing.
    public var referenceBlobID: UUID?

    /// Creates a request, dropping any picture the settings carry and clamping the count.
    public init(
        modelID: String, count: Int, settings: GenerationSettings, referenceBlobID: UUID? = nil,
        requestID: UUID = UUID()
    ) {
        self.requestID = requestID
        self.modelID = modelID
        self.count = min(max(count, Self.countBounds.lowerBound), Self.countBounds.upperBound)
        self.settings = settings.withoutPixels()
        self.referenceBlobID = referenceBlobID
    }
}
