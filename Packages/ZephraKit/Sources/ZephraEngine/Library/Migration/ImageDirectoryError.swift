import Foundation

/// A folder change that could not safely finish.
public struct ImageDirectoryError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
