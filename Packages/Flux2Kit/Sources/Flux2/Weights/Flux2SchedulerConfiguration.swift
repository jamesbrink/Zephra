import Foundation

/// `scheduler/scheduler_config.json`: the flow-matching noise schedule.
///
/// The published file also carries `base_shift`, `max_shift`, `shift`, and the sequence lengths
/// they are measured at. They are not decoded because klein's pipeline never reads them: it
/// computes its shift from the image's token count and the step count directly, with the
/// constants in `EmpiricalShift`. Decoding them would invite someone to use them.
public struct Flux2SchedulerConfiguration: Hashable, Sendable, Decodable {
    /// Steps the model was trained over.
    public let numTrainTimesteps: Int
    /// Whether the shift is computed from the image's token count. It is.
    public let useDynamicShifting: Bool
    /// The value the last sigma is stretched to reach, or nil to leave the tail alone. klein
    /// leaves it alone.
    public let shiftTerminal: Double?
    /// How the shift is applied. FLUX.2 uses `exponential`.
    public let timeShiftType: String

    enum CodingKeys: String, CodingKey {
        case numTrainTimesteps = "num_train_timesteps"
        case useDynamicShifting = "use_dynamic_shifting"
        case shiftTerminal = "shift_terminal"
        case timeShiftType = "time_shift_type"
    }
}
