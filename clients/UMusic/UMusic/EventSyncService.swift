import Foundation

actor EventSyncService {
    private let api: any MusicAPI
    private let fileURL: URL
    private var pending: [ListeningEvent]

    init(api: any MusicAPI = APIClient(), directory: URL? = nil) {
        self.api = api
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        fileURL = base.appending(path: "uMusic/pending-events.json")
        pending = (try? Data(contentsOf: fileURL)).flatMap {
            try? JSONDecoder.uMusic.decode([ListeningEvent].self, from: $0)
        } ?? []
    }

    func append(_ event: ListeningEvent) {
        pending.append(event)
        persist()
    }

    func flush(server: URL, token: String) async throws {
        guard !pending.isEmpty else { return }
        let batch = Array(pending.prefix(500))
        try await api.upload(server: server, token: token, events: batch)
        let sent = Set(batch.map(\.clientEventID))
        pending.removeAll { sent.contains($0.clientEventID) }
        persist()
    }

    func count() -> Int { pending.count }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder.uMusic.encode(pending).write(to: fileURL, options: .atomic)
        } catch {
            // Events remain in memory and the next append retries persistence.
        }
    }
}
