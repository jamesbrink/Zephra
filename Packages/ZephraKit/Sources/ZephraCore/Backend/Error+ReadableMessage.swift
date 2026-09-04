import Foundation

extension Error {
    /// The most specific description this error carries: `LocalizedError` text when whoever
    /// threw it wrote one, and the type's own description otherwise, since plenty of error
    /// cases in the libraries underneath carry no message of their own.
    ///
    /// A system error — a Cocoa, URL, or POSIX one — has a sentence of its own ("The network
    /// connection was lost.") that its description buries in a domain and a code, so those take
    /// the sentence. A Swift error with no text of its own keeps its case name rather than the
    /// "operation couldn't be completed" boilerplate `localizedDescription` would wrap it in.
    ///
    /// This is the last step before an error becomes something a person reads, so it never
    /// returns an empty string and never invents one.
    public var readableMessage: String {
        if let text = (self as? any LocalizedError)?.errorDescription { return text }
        let bridged = self as NSError
        if Self.systemDomains.contains(bridged.domain) { return bridged.localizedDescription }
        return String(describing: self)
    }

    private static var systemDomains: Set<String> {
        [NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain]
    }
}
