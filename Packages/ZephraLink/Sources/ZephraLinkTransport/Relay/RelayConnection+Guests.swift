import Foundation
import ZephraLinkProtocol

/// Writing to one of the several phones a room may hold.
///
/// The relay gives a host one socket for all of them, so the guest a frame is for is written on
/// the frame itself. A host that names none is answered `ambiguous` where the room holds more
/// than one, which is a frame refused rather than a sealed frame opened by the wrong phone.
extension RelayConnection {
}
