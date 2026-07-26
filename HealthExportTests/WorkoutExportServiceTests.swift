import HealthKit
import XCTest
@testable import HealthExport

@MainActor
final class WorkoutExportServiceTests: XCTestCase {
    private var recordedHistory: [PushHistoryEntry] = []

    override func setUp() {
        super.setUp()
        recordedHistory = []
        MockURLProtocol.requestHandler = nil
    }

    func testPushRecordsSuccessForHTTP2xx() async throws {
        let workout = makeWorkout()
        let server = makeServer()
        let manager = StubWorkoutDataProvider(
            isAuthorised: true,
            workouts: [workout],
            metrics: ["heart_rate": []]
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), workout.uuid.uuidString)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workout-Source"), "apple-health-export")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"ok\":true}".utf8))
        }

        let service = WorkoutExportService(
            healthKitManager: manager,
            urlSession: MockURLSessionFactory.makeSession()
        ) { [weak self] entry in
            self?.recordedHistory.append(entry)
        }

        let summary = try await service.pushLatestWorkout(
            to: [server],
            secretProvider: { _ in "test-token" }
        )

        XCTAssertTrue(summary.allSucceeded)
        XCTAssertEqual(summary.succeededCount, 1)
        XCTAssertEqual(recordedHistory.count, 1)
        XCTAssertEqual(recordedHistory.first?.status, .success)
        XCTAssertEqual(recordedHistory.first?.statusCode, 201)
        XCTAssertEqual(recordedHistory.first?.workoutHealthKitUUID, workout.uuid)
        XCTAssertEqual(recordedHistory.first?.workout?.activityType, "running")
        XCTAssertNotNil(recordedHistory.first?.pushStartedAt)
        XCTAssertNotNil(recordedHistory.first?.pushDurationFormatted)
    }

    func testPushRecordsFailureForHTTP5xx() async throws {
        let workout = makeWorkout()
        let server = makeServer()
        let manager = StubWorkoutDataProvider(
            isAuthorised: true,
            workouts: [workout],
            metrics: [:]
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("service unavailable".utf8))
        }

        let service = WorkoutExportService(
            healthKitManager: manager,
            urlSession: MockURLSessionFactory.makeSession()
        ) { [weak self] entry in
            self?.recordedHistory.append(entry)
        }

        let summary = try await service.pushLatestWorkout(to: [server], secretProvider: { _ in nil })

        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(recordedHistory.first?.statusCode, 503)
        XCTAssertEqual(recordedHistory.first?.status, .failure)
        XCTAssertEqual(recordedHistory.first?.workout?.activityType, "running")
    }

    func testPushRecordsFailureForHTTP4xx() async throws {
        let workout = makeWorkout()
        let server = makeServer()
        let manager = StubWorkoutDataProvider(
            isAuthorised: true,
            workouts: [workout],
            metrics: [:]
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 422,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("validation failed".utf8))
        }

        let service = WorkoutExportService(
            healthKitManager: manager,
            urlSession: MockURLSessionFactory.makeSession()
        ) { [weak self] entry in
            self?.recordedHistory.append(entry)
        }

        let summary = try await service.pushLatestWorkout(to: [server], secretProvider: { _ in nil })

        XCTAssertFalse(summary.allSucceeded)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(recordedHistory.first?.status, .failure)
        XCTAssertEqual(recordedHistory.first?.statusCode, 422)
        XCTAssertTrue(recordedHistory.first?.message?.contains("422") == true)
    }

    func testPushRecordsTransportError() async throws {
        let workout = makeWorkout()
        let server = makeServer()
        let manager = StubWorkoutDataProvider(
            isAuthorised: true,
            workouts: [workout],
            metrics: [:]
        )

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = WorkoutExportService(
            healthKitManager: manager,
            urlSession: MockURLSessionFactory.makeSession()
        ) { [weak self] entry in
            self?.recordedHistory.append(entry)
        }

        let summary = try await service.pushLatestWorkout(to: [server], secretProvider: { _ in nil })

        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(recordedHistory.first?.status, .failure)
        XCTAssertNil(recordedHistory.first?.statusCode)
        XCTAssertFalse(recordedHistory.first?.message?.isEmpty == true)
    }

    func testPushFailureMessageCapsResponseSnippetAt500Characters() async throws {
        let workout = makeWorkout()
        let server = makeServer()
        let manager = StubWorkoutDataProvider(
            isAuthorised: true,
            workouts: [workout],
            metrics: [:]
        )
        let longBody = String(repeating: "x", count: 600)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(longBody.utf8))
        }

        let service = WorkoutExportService(
            healthKitManager: manager,
            urlSession: MockURLSessionFactory.makeSession()
        ) { [weak self] entry in
            self?.recordedHistory.append(entry)
        }

        let summary = try await service.pushLatestWorkout(to: [server], secretProvider: { _ in nil })

        XCTAssertEqual(summary.failedCount, 1)
        let rawMessage = summary.workoutResults.first?.message
        XCTAssertTrue(rawMessage?.hasPrefix("HTTP 500: ") == true)
        let snippet = rawMessage?.dropFirst("HTTP 500: ".count)
        XCTAssertEqual(snippet?.count, 500)
    }

    func testPushRequiresAuthorisedHealthKit() async {
        let manager = StubWorkoutDataProvider(isAuthorised: false, workouts: [], metrics: [:])
        let service = WorkoutExportService(
            healthKitManager: manager,
            urlSession: MockURLSessionFactory.makeSession()
        ) { _ in }

        do {
            _ = try await service.pushLatestWorkout(to: [makeServer()], secretProvider: { _ in nil })
            XCTFail("Expected HealthKit authorisation error")
        } catch let error as WorkoutExportError {
            XCTAssertEqual(error, .healthKitNotAuthorised)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeServer() -> DestinationServer {
        DestinationServer(
            name: "Test",
            host: "example.com",
            uploadPath: "/workouts",
            isEnabled: true,
            auth: .init(type: .bearer, headerName: nil)
        )
    }

    private func makeWorkout() -> HKWorkout {
        HKWorkout(
            activityType: .running,
            start: Date(timeIntervalSince1970: 1_735_732_800),
            end: Date(timeIntervalSince1970: 1_735_734_600)
        )
    }
}

@MainActor
private final class StubWorkoutDataProvider: WorkoutDataProviding {
    var isAuthorised: Bool
    private let workouts: [HKWorkout]
    private let metrics: [String: Any]

    init(isAuthorised: Bool, workouts: [HKWorkout], metrics: [String: Any]) {
        self.isAuthorised = isAuthorised
        self.workouts = workouts
        self.metrics = metrics
    }

    func fetchWorkouts(limit: Int) async throws -> [HKWorkout] {
        if limit == HKObjectQueryNoLimit {
            return workouts
        }
        return Array(workouts.prefix(limit))
    }

    func fetchAllMetrics(for workout: HKWorkout) async throws -> [String: Any] {
        metrics
    }
}
