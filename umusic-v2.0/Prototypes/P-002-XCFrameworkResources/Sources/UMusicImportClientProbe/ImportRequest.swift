import Foundation

public struct ImportRequest: Codable, Equatable, Sendable {
    public let sourceURL: URL
    public let idempotencyKey: UUID

    public init(sourceURL: URL, idempotencyKey: UUID) throws {
        guard let scheme = sourceURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw ImportRequestError.unsupportedScheme
        }
        self.sourceURL = sourceURL
        self.idempotencyKey = idempotencyKey
    }
}

public enum ImportRequestError: Error, Equatable {
    case unsupportedScheme
}

