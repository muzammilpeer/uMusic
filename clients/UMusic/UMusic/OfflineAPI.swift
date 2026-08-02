import Foundation

protocol OfflineMusicAPI: Sendable {
    func activities(server: URL, token: String) async throws -> [ActivityOption]
    func generateSession(
        server: URL, token: String, activityID: UUID, duration: Int, energy: Double
    ) async throws -> GeneratedSession
    func createSyncPlan(
        server: URL, token: String, deviceID: UUID, playlistID: UUID
    ) async throws -> SyncPlanResponse
    func manifest(server: URL, token: String, planID: UUID) async throws -> SyncManifest
    func acknowledge(
        server: URL, token: String, planID: UUID, downloaded: [UUID], failed: [UUID]
    ) async throws
    func createPlaybackSession(
        server: URL, token: String, trackIDs: [UUID], contextSnapshotID: UUID?
    ) async throws -> PlaybackSessionResponse
    func continuation(
        server: URL, token: String, sessionID: UUID, recommendationID: UUID,
        existingTrackIDs: [UUID], desiredCount: Int
    ) async throws -> ContinuationResponse
}

extension APIClient: OfflineMusicAPI {
    func activities(server: URL, token: String) async throws -> [ActivityOption] {
        try await offlineSend(
            offlineRequest(server.appending(path: "api/v1/contexts/activities/"), token: token),
            as: [ActivityOption].self
        )
    }

    func generateSession(
        server: URL, token: String, activityID: UUID, duration: Int, energy: Double
    ) async throws -> GeneratedSession {
        var request = offlineRequest(
            server.appending(path: "api/v1/recommendations/session-playlist/"), token: token
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "activity_id": activityID.uuidString,
            "duration_minutes": duration,
            "target_energy": energy,
            "discovery": 0.2,
            "offline": true,
            "seed": Int.random(in: 0..<Int.max),
        ])
        return try await offlineSend(request, as: GeneratedSession.self)
    }

    func createSyncPlan(
        server: URL, token: String, deviceID: UUID, playlistID: UUID
    ) async throws -> SyncPlanResponse {
        var request = offlineRequest(
            server.appending(
                path: "api/v1/devices/\(deviceID.uuidString.lowercased())/sync-plans"
            ), token: token
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "playlist_id": playlistID.uuidString
        ])
        return try await offlineSend(request, as: SyncPlanResponse.self)
    }

    func manifest(server: URL, token: String, planID: UUID) async throws -> SyncManifest {
        try await offlineSend(
            offlineRequest(
                server.appending(
                    path: "api/v1/sync-plans/\(planID.uuidString.lowercased())/manifest"
                ), token: token
            ),
            as: SyncManifest.self
        )
    }

    func acknowledge(
        server: URL, token: String, planID: UUID, downloaded: [UUID], failed: [UUID]
    ) async throws {
        var request = offlineRequest(
            server.appending(
                path: "api/v1/sync-plans/\(planID.uuidString.lowercased())/acknowledge"
            ), token: token
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "downloaded_track_ids": downloaded.map(\.uuidString),
            "failed_track_ids": failed.map(\.uuidString),
        ])
        let _: SyncPlanResponse = try await offlineSend(request, as: SyncPlanResponse.self)
    }

    func createPlaybackSession(
        server: URL, token: String, trackIDs: [UUID], contextSnapshotID: UUID?
    ) async throws -> PlaybackSessionResponse {
        var request = offlineRequest(
            server.appending(path: "api/v1/playback/sessions/"), token: token
        )
        request.httpMethod = "POST"
        var body: [String: Any] = ["track_ids": trackIDs.map(\.uuidString)]
        if let contextSnapshotID { body["context_snapshot_id"] = contextSnapshotID.uuidString }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await offlineSend(request, as: PlaybackSessionResponse.self)
    }

    func continuation(
        server: URL, token: String, sessionID: UUID, recommendationID: UUID,
        existingTrackIDs: [UUID], desiredCount: Int
    ) async throws -> ContinuationResponse {
        var request = offlineRequest(
            server.appending(
                path: "api/v1/playback/sessions/\(sessionID.uuidString.lowercased())/continuations/"
            ),
            token: token
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "recommendation_version_id": recommendationID.uuidString,
            "played_track_ids": existingTrackIDs.map(\.uuidString),
            "desired_count": desiredCount,
        ])
        return try await offlineSend(request, as: ContinuationResponse.self)
    }

    private func offlineRequest(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func offlineSend<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }
        return try JSONDecoder.uMusic.decode(T.self, from: data)
    }
}
