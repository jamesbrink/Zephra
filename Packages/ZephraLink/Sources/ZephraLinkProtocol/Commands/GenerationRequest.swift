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
    /// Everything else the user chose. Its pictures are always without their bytes here.
    public private(set) var settings: GenerationSettings
    /// The blobs already sent that hold the reference pictures, in the order the model reads
    /// them, and empty for a run from nothing.
    ///
    /// One blob each rather than one blob holding all of them: a blob is announced and sent on
    /// its own, and a phone that sends five pictures and then asks for a generation is five
    /// transfers the Mac can evict independently.
    public var referenceBlobIDs: [UUID]

    /// The first of those blobs, which is what a Mac reading one picture asks for. Setting it
    /// replaces the whole list, as `GenerationSettings.referenceImage` does.
    public var referenceBlobID: UUID? {
        get { referenceBlobIDs.first }
        set { referenceBlobIDs = newValue.map { [$0] } ?? [] }
    }

    /// Creates a request, dropping any picture's bytes from the settings and clamping the count.
    public init(
        modelID: String, count: Int, settings: GenerationSettings, referenceBlobID: UUID? = nil,
        referenceBlobIDs: [UUID] = [], requestID: UUID = UUID()
    ) {
        self.requestID = requestID
        self.modelID = modelID
        self.count = min(max(count, Self.countBounds.lowerBound), Self.countBounds.upperBound)
        self.settings = settings.withoutPixels()
        // The list where there is one, and otherwise the single id an older build sends: passing
        // both is a programmer error, and the list is what wins.
        self.referenceBlobIDs = referenceBlobIDs.isEmpty
            ? (referenceBlobID.map { [$0] } ?? []) : referenceBlobIDs
    }
}
