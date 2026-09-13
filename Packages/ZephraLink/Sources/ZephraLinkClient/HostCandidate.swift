import Foundation
import ZephraLinkProtocol

public struct HostCandidate: Sendable {
        public let id: HostID
        public let offer: HostOffer
        public let age: Double
        public let pendingSeconds: Double
        public init(id: HostID, offer: HostOffer, age: Double = 0, pendingSeconds: Double = 0) {
            self.id = id; self.offer = offer; self.age = age; self.pendingSeconds = pendingSeconds
        }
        public var eligible: Bool {
            offer.refusal == nil && age >= 0 && age <= min(offer.lifetime, 5)
                && offer.memoryMargin >= 0 && offer.memoryMargin.isFinite
                && offer.lifetime.isFinite && offer.queueCount >= 0
                && pendingSeconds.isFinite && pendingSeconds >= 0
                && [offer.queueSeconds, offer.preparationSeconds, offer.executionSeconds]
                    .allSatisfy { $0 == nil || ($0!.isFinite && $0! >= 0) }
        }
    }
