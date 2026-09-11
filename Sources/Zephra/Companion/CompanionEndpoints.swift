import Foundation
import ZephraLinkProtocol

/// Where a phone should try to reach this Mac, as the QR code says it.
///
/// Addresses rather than Bonjour alone. A phone that has just read a code should connect on the
/// first try, and a browse takes a second or two and sometimes longer on a busy network; the
/// `.local` name is still first in the list, because it survives a Mac being handed a different
/// address by the router, and the literal addresses behind it are what work when multicast DNS
/// does not.
///
/// At most `PairingPayload.endpointLimit`, best first, and the loopback and every link-local
/// address left out: a code is photographed across a desk, and an address only this Mac can
/// reach is a line the phone would try and wait on for nothing.
enum CompanionEndpoints {
    /// The port the Mac listens on. Fixed rather than chosen, so a phone that has paired can
    /// knock without being told again and a home router can be given one rule.
    static let port: UInt16 = 7723

    /// This Mac's addresses, for the code on screen.
    static func current(port: UInt16 = port) -> [Endpoint] {
        (localName(port: port).map { [$0] } ?? []) + addresses()
            .prefix(PairingPayload.endpointLimit)
            .map { Endpoint(host: $0, port: port) }
    }

    /// The Mac's Bonjour name, `something.local`, or nil when it has not got one.
    private static func localName(port: UInt16 = port) -> Endpoint? {
        let name = ProcessInfo.processInfo.hostName
        guard name.hasSuffix(".local") else { return nil }
        return Endpoint(host: name, port: port)
    }

    /// Every IPv4 address on an interface that is up and is not the loopback, in the order the
    /// system lists them — which puts the built-in interfaces before the virtual ones.
    ///
    /// IPv4 only, and deliberately: a link-local IPv6 address needs a scope id to be dialled and
    /// carrying one across a QR code would be four more characters for an address a phone on the
    /// same Wi-Fi reaches by its v4 one anyway.
    static func addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [String] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = interface.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET),
                interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                let text = text(of: address, length: interface.pointee.ifa_addr.pointee.sa_len),
                !text.hasPrefix("169.254."), !found.contains(text)
            else { continue }
            found.append(text)
        }
        return found
    }

    /// One socket address as the dotted quad a person would read off a code.
    private static func text(of address: UnsafeMutablePointer<sockaddr>, length: UInt8) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address, socklen_t(length), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
        guard status == 0 else { return nil }
        return String(cString: buffer)
    }
}
