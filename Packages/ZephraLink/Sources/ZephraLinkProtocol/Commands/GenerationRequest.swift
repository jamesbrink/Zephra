import Foundation
import ZephraCore

/// A press of Generate, asked for from the phone.
///
/// The settings are `ZephraCore`'s own, so the Mac clamps what arrives with the same `clamp`
/// every local press goes through and no second set of rules exists. The one thing stripped is
/// the reference picture: megabytes of PNG inside a JSON envelope would block the channel for
/// everything else, so a picture crosses as a blob and is named here by its id.
public struct GenerationRequest: Hashable, Sendable {
    /// The most seeds one press may ask for, which is the Mac's own batch limit.
    public static let countBounds = 1...8

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
        modelID: String, count: Int, settings: GenerationSettings, referenceBlobID: UUID? = nil
    ) {
        self.modelID = modelID
        self.count = min(max(count, Self.countBounds.lowerBound), Self.countBounds.upperBound)
        var stripped = settings
        stripped.referenceImage = nil
        self.settings = stripped
        self.referenceBlobID = referenceBlobID
    }
}
