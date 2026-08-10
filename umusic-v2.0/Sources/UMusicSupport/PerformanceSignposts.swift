import Foundation
import os

public enum PerformanceSignposts {
    private static let signposter = OSSignposter(subsystem: "uk.muzammilpeer.umusic.v2", category: "Performance")
    public struct Interval: @unchecked Sendable {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
    }
    public static func begin(_ name: StaticString) -> Interval { .init(name: name, state: signposter.beginInterval(name)) }
    public static func end(_ interval: Interval) { signposter.endInterval(interval.name, interval.state) }
}
