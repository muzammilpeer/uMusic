import Foundation

protocol WorkoutMusicAPI: Sendable {
    func workoutActivities(server: URL, token: String) async throws -> [WorkoutActivity]
    func places(server: URL, token: String) async throws -> [Place]
    func createCustomActivity(server: URL, token: String, name: String) async throws
        -> WorkoutActivity
    func createContext(
        server: URL, token: String, activityID: UUID, placeID: UUID?, phase: WorkoutPhase,
        durationMinutes: Int, targetEnergy: Double
    ) async throws -> ContextSnapshotResponse
}

extension APIClient: WorkoutMusicAPI {
    func workoutActivities(server: URL, token: String) async throws -> [WorkoutActivity] {
        try await workoutSend(
            workoutRequest(server.appending(path: "api/v1/contexts/activities/"), token: token),
            as: [WorkoutActivity].self
        )
    }

    func places(server: URL, token: String) async throws -> [Place] {
        try await workoutSend(
            workoutRequest(server.appending(path: "api/v1/contexts/geofences/"), token: token),
            as: [Place].self
        )
    }

    func createCustomActivity(server: URL, token: String, name: String) async throws
        -> WorkoutActivity {
        var request = workoutRequest(
            server.appending(path: "api/v1/contexts/activities/"), token: token
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name, "slug": "custom-\(UUID().uuidString.lowercased())",
            "phase_curve": ["steady"],
        ])
        return try await workoutSend(request, as: WorkoutActivity.self)
    }

    func createContext(
        server: URL, token: String, activityID: UUID, placeID: UUID?, phase: WorkoutPhase,
        durationMinutes: Int, targetEnergy: Double
    ) async throws -> ContextSnapshotResponse {
        var request = workoutRequest(
            server.appending(path: "api/v1/contexts/snapshots/"), token: token
        )
        request.httpMethod = "POST"
        var body: [String: Any] = [
            "activity_id": activityID.uuidString, "phase": phase.rawValue,
            "planned_duration_minutes": durationMinutes, "target_energy": targetEnergy,
            "discovery": 0.2,
        ]
        if let placeID { body["geofence_id"] = placeID.uuidString }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await workoutSend(request, as: ContextSnapshotResponse.self)
    }

    private func workoutRequest(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func workoutSend<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { throw APIError.invalidResponse }
        return try JSONDecoder.uMusic.decode(T.self, from: data)
    }
}
