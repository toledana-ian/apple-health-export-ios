import Foundation
import HealthKit

struct WorkoutPushAttemptResult: Equatable, Identifiable {
    var id: String { "\(workoutHealthKitUUID.uuidString)-\(serverId.uuidString)" }
    var workoutHealthKitUUID: UUID
    var serverId: UUID
    var serverName: String
    var success: Bool
    var statusCode: Int?
    var message: String?
    var workoutSnapshot: PushHistoryWorkoutSnapshot?
    var pushStartedAt: Date?
    var pushFinishedAt: Date?

    var outcomeSummary: String {
        if success {
            if let statusCode {
                return "Delivered (HTTP \(statusCode))"
            }
            return "Delivered"
        }
        if let statusCode, let message, !message.isEmpty {
            return "Failed (HTTP \(statusCode)): \(message)"
        }
        if let message, !message.isEmpty {
            return "Failed: \(message)"
        }
        if let statusCode {
            return "Failed (HTTP \(statusCode))"
        }
        return "Failed"
    }
}

struct WorkoutPushBatchSummary: Equatable {
    var workoutResults: [WorkoutPushAttemptResult]
    var succeededCount: Int
    var failedCount: Int

    var allSucceeded: Bool { failedCount == 0 && !workoutResults.isEmpty }

    var summaryText: String {
        if workoutResults.isEmpty {
            return "No delivery attempts were made."
        }
        if allSucceeded {
            return "All \(succeededCount) deliveries succeeded."
        }
        return "\(succeededCount) succeeded, \(failedCount) failed."
    }
}

enum WorkoutExportError: LocalizedError, Equatable {
    case healthKitNotAuthorised
    case noEnabledServers
    case noWorkoutsFound
    case workoutNotFound(UUID)
    case invalidUploadURL(String)

    var errorDescription: String? {
        switch self {
        case .healthKitNotAuthorised:
            return "HealthKit access is required before exporting workouts."
        case .noEnabledServers:
            return "Add and enable at least one destination server."
        case .noWorkoutsFound:
            return "No workouts were found in HealthKit."
        case .workoutNotFound(let uuid):
            return "Workout \(uuid.uuidString) was not found."
        case .invalidUploadURL(let message):
            return message
        }
    }
}

enum WorkoutPushMode: String, CaseIterable, Identifiable {
    case concurrent
    case sequential

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concurrent: return "Concurrent"
        case .sequential: return "Sequential"
        }
    }
}

private struct PreparedWorkoutPush: Sendable {
    var workoutUUID: UUID
    var body: Data
}

private struct WorkoutPushJob: Sendable {
    var index: Int
    var workoutID: UUID
    var prepared: PreparedWorkoutPush?
    var workoutSnapshot: PushHistoryWorkoutSnapshot?
    var prepareErrorMessage: String?
}

final class WorkoutExportService {
    static let responseSnippetLimit = 500
    static let workoutSourceHeader = "apple-health-export"

    private let healthKitManager: any WorkoutDataProviding
    private let urlSession: URLSessionProtocol
    private let recordHistory: @MainActor (PushHistoryEntry) -> Void

    init(
        healthKitManager: any WorkoutDataProviding,
        urlSession: URLSessionProtocol = URLSession.shared,
        recordHistory: @escaping @MainActor (PushHistoryEntry) -> Void
    ) {
        self.healthKitManager = healthKitManager
        self.urlSession = urlSession
        self.recordHistory = recordHistory
    }

    @MainActor
    convenience init(healthKitManager: HealthKitManager, serverStore: ServerStore) {
        self.init(healthKitManager: healthKitManager) { [serverStore] entry in
            serverStore.appendHistory(entry)
        }
    }

    func pushLatestWorkout(
        to servers: [DestinationServer],
        secretProvider: (DestinationServer) -> String?
    ) async throws -> WorkoutPushBatchSummary {
        try await validatePreconditions(servers: servers)

        let workouts = try await fetchWorkouts(limit: 1)
        guard let latest = workouts.first else {
            throw WorkoutExportError.noWorkoutsFound
        }

        return await pushWorkout(
            latest,
            to: enabledServers(from: servers),
            secretProvider: secretProvider
        )
    }

    func pushWorkouts(
        ids: [UUID],
        to server: DestinationServer,
        mode: WorkoutPushMode,
        secretProvider: (DestinationServer) -> String?,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> WorkoutPushBatchSummary {
        try await validateAuthorised()
        guard server.isEnabled else {
            throw WorkoutExportError.noEnabledServers
        }
        guard !ids.isEmpty else {
            return WorkoutPushBatchSummary(workoutResults: [], succeededCount: 0, failedCount: 0)
        }

        let workouts = try await fetchWorkouts(limit: 100)
        let workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.uuid, $0) })
        let secret = secretProvider(server)
        let total = ids.count
        var allResults: [WorkoutPushAttemptResult] = []

        switch mode {
        case .sequential:
            for (index, workoutID) in ids.enumerated() {
                await Self.reportProgress(onProgress, current: index + 1, total: total)
                let result = await pushPreparedWorkout(
                    workoutID: workoutID,
                    workout: workoutsByID[workoutID],
                    to: server,
                    secret: secret
                )
                allResults.append(result)
                await storeHistory(from: result)
            }
        case .concurrent:
            let jobs = await preparePushJobs(ids: ids, workoutsByID: workoutsByID)
            let urlSession = urlSession
            let pairs = await withTaskGroup(of: (Int, WorkoutPushAttemptResult).self) { group in
                for job in jobs {
                    group.addTask {
                        let result = await Self.deliverJob(
                            job,
                            to: server,
                            secret: secret,
                            urlSession: urlSession
                        )
                        return (job.index, result)
                    }
                }

                var collected: [(Int, WorkoutPushAttemptResult)] = []
                for await pair in group {
                    collected.append(pair)
                    await Self.reportProgress(onProgress, current: collected.count, total: total)
                }
                return collected.sorted { $0.0 < $1.0 }.map(\.1)
            }
            allResults = pairs
            for result in allResults {
                await storeHistory(from: result)
            }
        }

        return makeBatchSummary(from: allResults)
    }

    func recentWorkoutSummaries(limit: Int = 100) async throws -> [WorkoutSummary] {
        try await validateAuthorised()
        let workouts = try await fetchWorkouts(limit: limit)
        return workouts.map(WorkoutExportPayloadBuilder.summary(from:))
    }

    // MARK: - Private

    @MainActor
    private func validatePreconditions(servers: [DestinationServer]) throws {
        guard healthKitManager.isAuthorised else {
            throw WorkoutExportError.healthKitNotAuthorised
        }
        guard !enabledServers(from: servers).isEmpty else {
            throw WorkoutExportError.noEnabledServers
        }
    }

    @MainActor
    private func validateAuthorised() throws {
        guard healthKitManager.isAuthorised else {
            throw WorkoutExportError.healthKitNotAuthorised
        }
    }

    @MainActor
    private func fetchWorkouts(limit: Int) async throws -> [HKWorkout] {
        try await healthKitManager.fetchWorkouts(limit: limit)
    }

    @MainActor
    private func preparePush(for workout: HKWorkout) async throws -> PreparedWorkoutPush {
        let rawMetrics = try await healthKitManager.fetchAllMetrics(for: workout)
        let envelope = WorkoutExportPayloadBuilder.envelope(from: workout, metrics: rawMetrics)
        let body = try WorkoutExportPayloadBuilder.encodeJSON(envelope)
        return PreparedWorkoutPush(workoutUUID: workout.uuid, body: body)
    }

    @MainActor
    private func preparePushJobs(
        ids: [UUID],
        workoutsByID: [UUID: HKWorkout]
    ) async -> [WorkoutPushJob] {
        var jobs: [WorkoutPushJob] = []
        jobs.reserveCapacity(ids.count)

        for (index, workoutID) in ids.enumerated() {
            guard let workout = workoutsByID[workoutID] else {
                jobs.append(
                    WorkoutPushJob(
                        index: index,
                        workoutID: workoutID,
                        prepared: nil,
                        workoutSnapshot: nil,
                        prepareErrorMessage: nil
                    )
                )
                continue
            }

            let snapshot = PushHistoryWorkoutSnapshot(
                summary: WorkoutExportPayloadBuilder.summary(from: workout)
            )
            do {
                let prepared = try await preparePush(for: workout)
                jobs.append(
                    WorkoutPushJob(
                        index: index,
                        workoutID: workoutID,
                        prepared: prepared,
                        workoutSnapshot: snapshot,
                        prepareErrorMessage: nil
                    )
                )
            } catch {
                jobs.append(
                    WorkoutPushJob(
                        index: index,
                        workoutID: workoutID,
                        prepared: nil,
                        workoutSnapshot: snapshot,
                        prepareErrorMessage: error.localizedDescription
                    )
                )
            }
        }

        return jobs
    }

    @MainActor
    private func workoutSnapshot(for workout: HKWorkout) -> PushHistoryWorkoutSnapshot {
        PushHistoryWorkoutSnapshot(summary: WorkoutExportPayloadBuilder.summary(from: workout))
    }

    private func enabledServers(from servers: [DestinationServer]) -> [DestinationServer] {
        servers.filter(\.isEnabled)
    }

    private func pushWorkout(
        _ workout: HKWorkout,
        to servers: [DestinationServer],
        secretProvider: (DestinationServer) -> String?
    ) async -> WorkoutPushBatchSummary {
        let workoutSnapshot = await workoutSnapshot(for: workout)
        let prepared: PreparedWorkoutPush
        do {
            prepared = try await preparePush(for: workout)
        } catch {
            let results = servers.map { server in
                WorkoutPushAttemptResult(
                    workoutHealthKitUUID: workout.uuid,
                    serverId: server.id,
                    serverName: server.name,
                    success: false,
                    statusCode: nil,
                    message: error.localizedDescription,
                    workoutSnapshot: workoutSnapshot,
                    pushStartedAt: nil,
                    pushFinishedAt: Date()
                )
            }
            for result in results {
                await storeHistory(from: result)
            }
            return makeBatchSummary(from: results)
        }

        let urlSession = urlSession
        let deliveries = servers.map { server in
            (server, secretProvider(server))
        }
        let results = await withTaskGroup(of: WorkoutPushAttemptResult.self) { group in
            for (server, secret) in deliveries {
                group.addTask {
                    await Self.deliverPreparedPush(
                        prepared,
                        to: server,
                        secret: secret,
                        urlSession: urlSession,
                        workoutSnapshot: workoutSnapshot
                    )
                }
            }

            var collected: [WorkoutPushAttemptResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for result in results {
            await storeHistory(from: result)
        }

        return makeBatchSummary(from: results)
    }

    private func pushPreparedWorkout(
        workoutID: UUID,
        workout: HKWorkout?,
        to server: DestinationServer,
        secret: String?
    ) async -> WorkoutPushAttemptResult {
        guard let workout else {
            return Self.missingWorkoutResult(workoutID: workoutID, server: server)
        }

        let workoutSnapshot = await workoutSnapshot(for: workout)
        let pushStartedAt = Date()

        do {
            let prepared = try await preparePush(for: workout)
            var result = await Self.deliverPreparedPush(
                prepared,
                to: server,
                secret: secret,
                urlSession: urlSession,
                workoutSnapshot: workoutSnapshot,
                pushStartedAt: pushStartedAt
            )
            if result.workoutSnapshot == nil {
                result.workoutSnapshot = workoutSnapshot
            }
            return result
        } catch {
            let finishedAt = Date()
            return WorkoutPushAttemptResult(
                workoutHealthKitUUID: workout.uuid,
                serverId: server.id,
                serverName: server.name,
                success: false,
                statusCode: nil,
                message: error.localizedDescription,
                workoutSnapshot: workoutSnapshot,
                pushStartedAt: pushStartedAt,
                pushFinishedAt: finishedAt
            )
        }
    }

    private static func deliverJob(
        _ job: WorkoutPushJob,
        to server: DestinationServer,
        secret: String?,
        urlSession: URLSessionProtocol
    ) async -> WorkoutPushAttemptResult {
        if let prepareErrorMessage = job.prepareErrorMessage {
            return WorkoutPushAttemptResult(
                workoutHealthKitUUID: job.workoutID,
                serverId: server.id,
                serverName: server.name,
                success: false,
                statusCode: nil,
                message: prepareErrorMessage,
                workoutSnapshot: job.workoutSnapshot,
                pushStartedAt: nil,
                pushFinishedAt: Date()
            )
        }

        guard let prepared = job.prepared else {
            return missingWorkoutResult(
                workoutID: job.workoutID,
                server: server,
                workoutSnapshot: job.workoutSnapshot
            )
        }

        return await deliverPreparedPush(
            prepared,
            to: server,
            secret: secret,
            urlSession: urlSession,
            workoutSnapshot: job.workoutSnapshot
        )
    }

    private static func deliverPreparedPush(
        _ prepared: PreparedWorkoutPush,
        to server: DestinationServer,
        secret: String?,
        urlSession: URLSessionProtocol,
        workoutSnapshot: PushHistoryWorkoutSnapshot? = nil,
        pushStartedAt: Date? = nil
    ) async -> WorkoutPushAttemptResult {
        let startedAt = pushStartedAt ?? Date()

        switch ServerURLBuilder.uploadURL(for: server) {
        case .failure(let error):
            return WorkoutPushAttemptResult(
                workoutHealthKitUUID: prepared.workoutUUID,
                serverId: server.id,
                serverName: server.name,
                success: false,
                statusCode: nil,
                message: error.localizedDescription,
                workoutSnapshot: workoutSnapshot,
                pushStartedAt: startedAt,
                pushFinishedAt: Date()
            )
        case .success(let url):
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 60
                request.httpBody = prepared.body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(prepared.workoutUUID.uuidString, forHTTPHeaderField: "Idempotency-Key")
                request.setValue(workoutSourceHeader, forHTTPHeaderField: "X-Workout-Source")
                ServerConnectionTester.applyAuth(to: &request, server: server, secret: secret)

                let (data, response) = try await urlSession.data(for: request)
                let finishedAt = Date()
                guard let http = response as? HTTPURLResponse else {
                    return WorkoutPushAttemptResult(
                        workoutHealthKitUUID: prepared.workoutUUID,
                        serverId: server.id,
                        serverName: server.name,
                        success: false,
                        statusCode: nil,
                        message: "No HTTP response received.",
                        workoutSnapshot: workoutSnapshot,
                        pushStartedAt: startedAt,
                        pushFinishedAt: finishedAt
                    )
                }

                let success = (200 ... 299).contains(http.statusCode)
                let snippet = responseSnippet(from: data)
                let message: String?
                if success {
                    message = snippet.isEmpty ? nil : snippet
                } else {
                    message = snippet.isEmpty
                        ? "Server responded with HTTP \(http.statusCode)."
                        : "HTTP \(http.statusCode): \(snippet)"
                }

                return WorkoutPushAttemptResult(
                    workoutHealthKitUUID: prepared.workoutUUID,
                    serverId: server.id,
                    serverName: server.name,
                    success: success,
                    statusCode: http.statusCode,
                    message: message,
                    workoutSnapshot: workoutSnapshot,
                    pushStartedAt: startedAt,
                    pushFinishedAt: finishedAt
                )
            } catch {
                return WorkoutPushAttemptResult(
                    workoutHealthKitUUID: prepared.workoutUUID,
                    serverId: server.id,
                    serverName: server.name,
                    success: false,
                    statusCode: nil,
                    message: sanitisedTransportError(error, server: server),
                    workoutSnapshot: workoutSnapshot,
                    pushStartedAt: startedAt,
                    pushFinishedAt: Date()
                )
            }
        }
    }

    private static func missingWorkoutResult(
        workoutID: UUID,
        server: DestinationServer,
        workoutSnapshot: PushHistoryWorkoutSnapshot? = nil
    ) -> WorkoutPushAttemptResult {
        WorkoutPushAttemptResult(
            workoutHealthKitUUID: workoutID,
            serverId: server.id,
            serverName: server.name,
            success: false,
            statusCode: nil,
            message: WorkoutExportError.workoutNotFound(workoutID).localizedDescription,
            workoutSnapshot: workoutSnapshot,
            pushStartedAt: nil,
            pushFinishedAt: Date()
        )
    }

    private func storeHistory(from result: WorkoutPushAttemptResult) async {
        let finishedAt = result.pushFinishedAt ?? Date()
        let entry = PushHistoryEntry(
            serverId: result.serverId,
            serverName: result.serverName,
            workoutHealthKitUUID: result.workoutHealthKitUUID,
            timestamp: finishedAt,
            status: result.success ? .success : .failure,
            statusCode: result.statusCode,
            message: result.outcomeSummary,
            workout: result.workoutSnapshot,
            pushStartedAt: result.pushStartedAt
        )
        await recordHistory(entry)
    }

    private func makeBatchSummary(from results: [WorkoutPushAttemptResult]) -> WorkoutPushBatchSummary {
        let succeeded = results.filter(\.success).count
        return WorkoutPushBatchSummary(
            workoutResults: results,
            succeededCount: succeeded,
            failedCount: results.count - succeeded
        )
    }

    static func responseSnippet(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let text = String(data: data, encoding: .utf8) ?? ""
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= responseSnippetLimit {
            return collapsed
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: responseSnippetLimit)
        return String(collapsed[..<end])
    }

    private static func sanitisedTransportError(_ error: Error, server: DestinationServer) -> String {
        let nsError = error as NSError
        if server.usesInsecureHTTP,
            nsError.domain == NSURLErrorDomain,
            nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
        {
            return "HTTP blocked by App Transport Security. Use HTTPS or a local network host."
        }
        return error.localizedDescription
    }

    @MainActor
    private static func reportProgress(
        _ onProgress: (@MainActor (Int, Int) -> Void)?,
        current: Int,
        total: Int
    ) {
        onProgress?(current, total)
    }
}
