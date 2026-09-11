import ZephraCore
import ZephraLinkProtocol

/// What is on disk for each model, keyed the way the phone looks one up.
///
/// The key is the descriptor identifier as a plain string rather than `ModelDescriptor.ID`,
/// because that is what every command names a model by and what JSON can hold as an object key.
public enum AvailabilityProjection {
    /// The Mac's survey as the phone reads it.
    public static func availability(
        _ availability: [ModelDescriptor.ID: ModelAvailability]
    ) -> [String: AvailabilityDTO] {
        availability.reduce(into: [:]) { map, pair in
            map[pair.key] = AvailabilityDTO(pair.value)
        }
    }
}
