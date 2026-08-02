import Foundation
import XCTest
@testable import UMusicCore

final class UMusicCoreTests: XCTestCase {
    func testWorkoutPhaseChangesAtBoundaries() {
        let engine = WorkoutPhaseEngine(phases: [.warmup, .sustain, .cooldown], duration: 900)
        XCTAssertEqual(engine.phase(at: 0), .warmup)
        XCTAssertEqual(engine.phase(at: 300), .sustain)
        XCTAssertEqual(engine.phase(at: 899), .cooldown)
    }

    func testFutureRerankingPreservesCurrentAndPast() {
        let artist = ArtistSummary(id: UUID(), name: "Runner")
        func track(_ title: String, _ energy: Double) -> Track {
            Track(
                id: UUID(), title: title, artist: artist, album: nil, durationMS: 1_000,
                genres: [], energy: energy, streamPath: "/stream"
            )
        }
        let past = track("Past", 0.1)
        let current = track("Current", 0.2)
        let low = track("Low", 0.3)
        let high = track("High", 0.9)
        let result = FutureQueueReranker.rerank(
            [past, current, low, high], after: current.id, targetEnergy: 1
        )
        XCTAssertEqual(Array(result.prefix(2)), [past, current])
        XCTAssertEqual(result[2], high)
    }

    func testOfflineManifestDecodesPlaybackMetadata() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "version":1,
          "playlist_id":"00000000-0000-0000-0000-000000000002",
          "entries":[{
            "track_id":"00000000-0000-0000-0000-000000000003",
            "position":0,"title":"Road","artist":{"id":"00000000-0000-0000-0000-000000000004","name":"Rider"},
            "album":null,"duration_ms":180000,"genres":["electronic"],"energy":0.8,
            "stream_path":"/api/v1/tracks/00000000-0000-0000-0000-000000000003/stream/",
            "size_bytes":123,"sha256":"abc","metadata_version":1,"artwork_checksum":null,
            "download_url":"https://music.example/download","download_expires_at":"2026-08-02T12:00:00Z"
          }]
        }
        """
        let manifest = try JSONDecoder.uMusic.decode(SyncManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.entries.first?.track.artist.name, "Rider")
        XCTAssertEqual(manifest.entries.first?.track.durationMS, 180_000)
    }

    func testTrackContractDecodingAndQueueRestoration() throws {
        let json = """
        {"id":"44444444-4444-4444-8444-444444444444","title":"Example","artist":{"id":"11111111-1111-4111-8111-111111111111","name":"Artist"},"album":null,"duration_ms":125000,"genres":["electronic"],"energy":0.8,"stream_path":"/api/v1/tracks/44444444-4444-4444-8444-444444444444/stream/"}
        """.data(using: .utf8)!
        let track = try JSONDecoder.uMusic.decode(Track.self, from: json)
        XCTAssertEqual(track.durationText, "2:05")
        XCTAssertEqual(track.artist.name, "Artist")

        let suite = "UMusicCoreTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QueueStore(defaults: defaults)
        store.save([track])
        XCTAssertEqual(store.load(), [track])
    }

    func testEventBatchIsRemovedOnlyAfterAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let api = MockAPI()
        let service = EventSyncService(api: api, directory: directory)
        let event = ListeningEvent(
            clientEventID: UUID(), playbackID: UUID(),
            trackID: UUID(), eventType: "started", clientTimestamp: Date(),
            positionMS: 0, durationMS: 1000, listenedMSDelta: 0, offline: false
        )
        await service.append(event)
        let queuedBefore = await service.count()
        XCTAssertEqual(queuedBefore, 1)
        try await service.flush(
            server: URL(string: "https://music.example.com")!, token: "device-token"
        )
        let queuedAfter = await service.count()
        let uploaded = await api.uploadedCount()
        XCTAssertEqual(queuedAfter, 0)
        XCTAssertEqual(uploaded, 1)
    }
}

private actor MockAPI: MusicAPI {
    private var uploaded: [ListeningEvent] = []

    func deleteTrack(server: URL, token: String, trackID: UUID) async throws {}

    func currentSession(server: URL, token: String) async throws -> CurrentSessionResponse {
        fatalError("Not used by these tests")
    }

    func login(server: URL, username: String, password: String, deviceName: String) async throws
        -> LoginResponse { throw APIError.invalidResponse }
    func tracks(server: URL, token: String, query: String) async throws -> Page<Track> {
        throw APIError.invalidResponse
    }
    func playlists(server: URL, token: String) async throws -> [Playlist] {
        throw APIError.invalidResponse
    }
    func upload(server: URL, token: String, events: [ListeningEvent]) async throws {
        uploaded.append(contentsOf: events)
    }
    func uploadedCount() -> Int { uploaded.count }
}
