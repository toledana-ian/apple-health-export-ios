import XCTest
@testable import HealthExport

final class WorkoutExportPayloadTests: XCTestCase {
    func testEnvelopeUsesExpectedSchemaAndSource() throws {
        let metadata = WorkoutExportMetadata(
            id: "550e8400-e29b-41d4-a716-446655440000",
            startDate: "2026-01-01T10:00:00Z",
            endDate: "2026-01-01T10:30:00Z",
            durationSeconds: 1800,
            activityType: "running",
            activityTypeRaw: 37,
            totalDistanceMetres: 5000,
            totalEnergyKcal: 420,
            name: "Morning Run",
            source: "Apple Watch"
        )

        let envelope = WorkoutExportEnvelope(
            schemaVersion: 1,
            source: "apple_health_export_ios",
            sourceWorkoutId: metadata.id,
            exportedAt: "2026-01-01T10:31:00Z",
            workout: metadata,
            metrics: WorkoutExportMetrics(
                heartRate: [
                    MetricDataPoint(timestamp: 1_735_732_800, date: "2026-01-01T10:00:00Z", value: 145)
                ]
            )
        )

        let data = try WorkoutExportPayloadBuilder.encodeJSON(envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"schema_version\":1"))
        XCTAssertTrue(json.contains("\"source\":\"apple_health_export_ios\""))
        XCTAssertTrue(json.contains("\"source_workout_id\":\"550e8400-e29b-41d4-a716-446655440000\""))
        XCTAssertTrue(json.contains("\"exported_at\":\"2026-01-01T10:31:00Z\""))
        XCTAssertTrue(json.contains("\"activity_type\":\"running\""))
        XCTAssertTrue(json.contains("\"heart_rate\""))
    }

    func testMetricsParserPreservesHealthKitSeries() {
        let raw: [String: Any] = [
            "heart_rate": [
                [
                    "timestamp": 100.0,
                    "date": "2026-01-01T10:00:00Z",
                    "value": 150.0,
                ]
            ],
            "route": [
                [
                    "latitude": 37.0,
                    "longitude": -122.0,
                    "altitude": 10.0,
                    "timestamp": 100.0,
                    "date": "2026-01-01T10:00:00Z",
                    "horizontal_accuracy": 5.0,
                    "vertical_accuracy": 3.0,
                    "speed": 3.5,
                    "course": 90.0,
                ]
            ],
        ]

        let metrics = WorkoutExportPayloadBuilder.metrics(from: raw)

        XCTAssertEqual(metrics.heartRate?.count, 1)
        XCTAssertEqual(metrics.heartRate?.first?.value, 150)
        XCTAssertEqual(metrics.route?.count, 1)
        XCTAssertEqual(metrics.route?.first?.latitude, 37)
        XCTAssertEqual(metrics.runningPower, nil)
    }

    func testResponseSnippetIsCappedAt500Characters() {
        let longBody = String(repeating: "x", count: 600)
        let snippet = WorkoutExportService.responseSnippet(from: Data(longBody.utf8))
        XCTAssertEqual(snippet.count, 500)
    }
}
