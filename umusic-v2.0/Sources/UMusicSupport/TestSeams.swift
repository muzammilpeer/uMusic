import Foundation

public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedDateProvider: DateProviding {
    private let date: Date
    public init(_ date: Date) { self.date = date }
    public func now() -> Date { date }
}

public protocol UUIDProviding: Sendable {
    func next() async -> UUID
}

public struct SystemUUIDProvider: UUIDProviding {
    public init() {}
    public func next() async -> UUID { UUID() }
}

public actor SequenceUUIDProvider: UUIDProviding {
    private var values: [UUID]

    public init(values: [UUID]) {
        self.values = values
    }

    public func next() async -> UUID {
        values.isEmpty ? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) : values.removeFirst()
    }
}

public protocol RandomProviding: Sendable {
    func nextUnitInterval() async -> Double
}

public actor SeededRandomProvider: RandomProviding {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public func nextUnitInterval() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state) / Double(UInt64.max)
    }
}
