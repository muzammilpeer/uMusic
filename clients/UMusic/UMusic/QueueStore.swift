import Foundation

struct QueueStore {
    struct PlaybackState: Codable {
        let trackID: UUID
        let track: Track?
        let elapsed: Double
        let wasPlaying: Bool
        let wasOffline: Bool
    }

    let defaults: UserDefaults
    private let key = "playQueue"
    private let playbackKey = "playbackState"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func save(_ queue: [Track]) {
        defaults.set(try? JSONEncoder.uMusic.encode(queue), forKey: key)
    }

    func load() -> [Track] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder.uMusic.decode([Track].self, from: data)) ?? []
    }

    func savePlayback(_ state: PlaybackState) {
        defaults.set(try? JSONEncoder.uMusic.encode(state), forKey: playbackKey)
    }

    func loadPlayback() -> PlaybackState? {
        guard let data = defaults.data(forKey: playbackKey) else { return nil }
        return try? JSONDecoder.uMusic.decode(PlaybackState.self, from: data)
    }
}
