import Foundation
import os

public enum LogPrivacy: Sendable {
    case safe
    case sensitive
}

public struct LogField: Sendable {
    public let key: String
    public let value: String
    public let privacy: LogPrivacy

    public init(_ key: String, _ value: String, privacy: LogPrivacy) {
        self.key = key
        self.value = value
        self.privacy = privacy
    }
}

public protocol RedactedLogging: Sendable {
    func info(_ event: String, fields: [LogField])
    func error(_ event: String, fields: [LogField])
}

public struct RedactedLogger: RedactedLogging {
    private let logger: Logger

    public init(subsystem: String = "app.umusic.v2", category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ event: String, fields: [LogField] = []) {
        logger.info("\(render(event, fields: fields), privacy: .public)")
    }

    public func error(_ event: String, fields: [LogField] = []) {
        logger.error("\(render(event, fields: fields), privacy: .public)")
    }

    public func render(_ event: String, fields: [LogField]) -> String {
        let values = fields.map { field in
            "\(field.key)=\(field.privacy == .safe ? field.value : "<redacted>")"
        }
        return ([event] + values).joined(separator: " ")
    }
}

