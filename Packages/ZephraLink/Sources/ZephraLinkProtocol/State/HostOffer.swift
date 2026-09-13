import Foundation

/// The Mac's side-effect-free assessment of one exact request. Nil estimates stay unknown.
public struct HostOffer: Codable, Hashable, Sendable {
    public var refusal: String?
    public var queueSeconds: Double?
    public var preparationSeconds: Double?
    public var executionSeconds: Double?
    public var finalizationSeconds: Double?
    public var inputTransferSeconds: Double?
    public var requiresInputTransfer: Bool?
    public var timingSampleCount: Int?
    public var estimateConfidence: String {
        guard totalSeconds != nil else { return "unknown" }
        return (timingSampleCount ?? 0) >= 3 ? "measured" : "limited"
    }
    public var memoryMargin: Double
    public var modelLoaded: Bool
    public var queueCount: Int
    public var queueRevision: String
    public var lifetime: Double
    public var physicalMemory: UInt64
    public var thermalState: Int
    public var totalSeconds: Double? {
        guard let queueSeconds, let preparationSeconds, let executionSeconds else { return nil }
        if requiresInputTransfer == true && inputTransferSeconds == nil { return nil }
        return queueSeconds + preparationSeconds + executionSeconds + (finalizationSeconds ?? 0) + (inputTransferSeconds ?? 0)
    }
    public init(refusal: String?, queueSeconds: Double?, preparationSeconds: Double?,
                executionSeconds: Double?, memoryMargin: Double, modelLoaded: Bool,
                queueCount: Int, queueRevision: String, physicalMemory: UInt64,
                thermalState: Int = 0, lifetime: Double = 5, finalizationSeconds: Double? = nil,
                inputTransferSeconds: Double? = nil, requiresInputTransfer: Bool? = nil, timingSampleCount: Int? = nil) {
        self.refusal = refusal; self.queueSeconds = queueSeconds
        self.preparationSeconds = preparationSeconds; self.executionSeconds = executionSeconds
        self.memoryMargin = memoryMargin; self.modelLoaded = modelLoaded
        self.queueCount = queueCount; self.queueRevision = queueRevision
        self.physicalMemory = physicalMemory; self.thermalState = thermalState
        self.lifetime = lifetime
        self.finalizationSeconds = finalizationSeconds; self.inputTransferSeconds = inputTransferSeconds
        self.requiresInputTransfer = requiresInputTransfer; self.timingSampleCount = timingSampleCount
    }
}
