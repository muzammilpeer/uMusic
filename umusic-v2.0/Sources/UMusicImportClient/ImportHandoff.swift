import Foundation

public protocol ImportJobSubmitting: Sendable {
    func submit(_ request: ImportRequest, server: URL, token: String) async throws -> ImportJob
    func status(jobID: UUID, server: URL, token: String) async throws -> ImportJob
}

public struct URLSessionImportJobClient: ImportJobSubmitting {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func submit(_ importRequest: ImportRequest, server: URL, token: String) async throws -> ImportJob {
        let url = server.appending(path: "api/v1/adapters/remote/")
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The extension's single Send action is presented with explicit rights/availability copy.
        request.httpBody = try JSONEncoder().encode(Body(url: importRequest.sourceURL.absoluteString, idempotencyKey: importRequest.idempotencyKey, attested: true))
        return try await perform(request)
    }

    public func status(jobID: UUID, server: URL, token: String) async throws -> ImportJob {
        var request = URLRequest(url: server.appending(path: "api/v1/adapters/jobs/\(jobID.uuidString.lowercased())/"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> ImportJob {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ImportClientError.invalidResponse }
            if http.statusCode == 401 { throw ImportClientError.authenticationUnavailable }
            if http.statusCode == 404 { throw ImportClientError.providerUnavailable }
            guard (200..<300).contains(http.statusCode) else { throw ImportClientError.serverUnavailable }
            guard let job = try? JSONDecoder().decode(ImportJob.self, from: data) else { throw ImportClientError.invalidResponse }
            return job
        } catch let error as ImportClientError { throw error }
        catch { throw ImportClientError.offline }
    }

    private struct Body: Codable {
        let url: String; let idempotencyKey: UUID; let attested: Bool
        enum CodingKeys: String, CodingKey { case url, idempotencyKey = "idempotency_key", attested }
    }
}

public actor AppGroupImportHandoff {
    private let defaults: UserDefaults
    private let key = "umusic.v2.pending-imports"
    public init(suiteName: String) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw ImportClientError.serverUnavailable }
        self.defaults = defaults
    }
    public init(defaults: UserDefaults) { self.defaults = defaults }

    @discardableResult public func enqueue(_ request: ImportRequest) throws -> Bool {
        var jobs = pending()
        guard !jobs.contains(where: { $0.idempotencyKey == request.idempotencyKey }) else { return false }
        jobs.append(request); try persist(jobs); return true
    }
    public func pending() -> [ImportRequest] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ImportRequest].self, from: data)) ?? []
    }
    public func remove(idempotencyKey: UUID) throws {
        try persist(pending().filter { $0.idempotencyKey != idempotencyKey })
    }
    private func persist(_ requests: [ImportRequest]) throws { defaults.set(try JSONEncoder().encode(requests), forKey: key) }
}

public enum ImportDeepLink {
    public static func job(_ id: UUID) -> URL { URL(string: "umusic://imports/jobs/\(id.uuidString.lowercased())")! }
}

public actor ImportHandoffProcessor {
    private let handoff: AppGroupImportHandoff
    private let credentials: any ImportCredentialStoring
    private let client: any ImportJobSubmitting
    public init(handoff: AppGroupImportHandoff, credentials: any ImportCredentialStoring, client: any ImportJobSubmitting) {
        self.handoff = handoff; self.credentials = credentials; self.client = client
    }

    /// Successful requests are removed; offline failures remain for an explicit later retry.
    public func submitPending() async throws -> [ImportJob] {
        guard let credentials = try await credentials.load() else { throw ImportClientError.authenticationUnavailable }
        var jobs: [ImportJob] = []
        for request in await handoff.pending() {
            let job = try await client.submit(request, server: credentials.server, token: credentials.accessToken)
            try await handoff.remove(idempotencyKey: request.idempotencyKey)
            jobs.append(job)
        }
        return jobs
    }
}
