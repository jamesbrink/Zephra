import Foundation

extension Error {
    /// The most specific description this error carries: `LocalizedError` text when whoever
    /// threw it wrote one, and the type's own description otherwise, since plenty of error
    /// cases in the libraries underneath carry no message of their own.
    ///
    /// This is the last step before an error becomes something a person reads, so it never
    /// returns an empty string and never invents one.
    public var readableMessage: String {
        (self as? any LocalizedError)?.errorDescription ?? String(describing: self)
    }
}
