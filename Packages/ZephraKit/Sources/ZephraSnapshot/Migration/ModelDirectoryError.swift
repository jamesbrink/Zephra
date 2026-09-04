import Foundation

/// A folder change that could not safely proceed.
public struct ModelDirectoryError: LocalizedError, Sendable {
    public let errorDescription: String?

    public init(_ message: String) { errorDescription = message }
}
