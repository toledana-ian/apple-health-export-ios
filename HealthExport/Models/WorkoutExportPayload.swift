import Foundation
import HealthKit

// MARK: - Export envelope

struct WorkoutExportEnvelope: Codable, Equatable {
    static let schemaVersion = 1
    static let sourceIdentifier = "apple_health_export_ios"

    var schemaVersion: Int
    var source: String
    var sourceWorkoutId: String
    var exportedAt: String
    var workout: WorkoutExportMetadata
    var metrics: WorkoutExportMetrics

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source
        case sourceWorkoutId = "source_workout_id"
        case exportedAt = "exported_at"
        case workout
        case metrics
    }
}

struct WorkoutExportMetadata: Codable, Equatable {
    var id: String
    var startDate: String
    var endDate: String
    var durationSeconds: Double
    var activityType: String
    var activityTypeRaw: UInt
    var totalDistanceMetres: Double?
    var totalEnergyKcal: Double?
    var name: String?
    var source: String

    enum CodingKeys: String, CodingKey {
        case id
        case startDate = "start_date"
        case endDate = "end_date"
        case durationSeconds = "duration_seconds"
        case activityType = "activity_type"
        case activityTypeRaw = "activity_type_raw"
        case totalDistanceMetres = "total_distance_metres"
        case totalEnergyKcal = "total_energy_kcal"
        case name
        case source
    }
}

struct MetricDataPoint: Codable, Equatable {
    var timestamp: Double
    var date: String
    var value: Double
}

struct RouteDataPoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Double
    var date: String
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var speed: Double
    var course: Double

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case altitude
        case timestamp
        case date
        case horizontalAccuracy = "horizontal_accuracy"
        case verticalAccuracy = "vertical_accuracy"
        case speed
        case course
    }
}

struct WorkoutExportMetrics: Codable, Equatable {
    var heartRate: [MetricDataPoint]?
    var runningPower: [MetricDataPoint]?
    var runningSpeed: [MetricDataPoint]?
    var strideLength: [MetricDataPoint]?
    var verticalOscillation: [MetricDataPoint]?
    var groundContactTime: [MetricDataPoint]?
    var route: [RouteDataPoint]?

    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case runningPower = "running_power"
        case runningSpeed = "running_speed"
        case strideLength = "stride_length"
        case verticalOscillation = "vertical_oscillation"
        case groundContactTime = "ground_contact_time"
        case route
    }
}

// MARK: - UI summary

struct WorkoutSummary: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var activityType: String
    var startDate: Date
    var durationSeconds: Double
    var totalDistanceMetres: Double?
    var totalEnergyKcal: Double?

    var durationFormatted: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var distanceFormatted: String? {
        guard let metres = totalDistanceMetres else { return nil }
        if metres >= 1000 {
            return String(format: "%.2f km", metres / 1000)
        }
        return String(format: "%.0f m", metres)
    }

    var energyFormatted: String? {
        guard let kcal = totalEnergyKcal else { return nil }
        return String(format: "%.0f kcal", kcal)
    }
}

// MARK: - Builder

enum WorkoutExportPayloadBuilder {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    static func envelope(
        from workout: HKWorkout,
        metrics rawMetrics: [String: Any],
        exportedAt: Date = Date()
    ) -> WorkoutExportEnvelope {
        WorkoutExportEnvelope(
            schemaVersion: WorkoutExportEnvelope.schemaVersion,
            source: WorkoutExportEnvelope.sourceIdentifier,
            sourceWorkoutId: workout.uuid.uuidString,
            exportedAt: isoFormatter.string(from: exportedAt),
            workout: metadata(from: workout),
            metrics: metrics(from: rawMetrics)
        )
    }

    static func metadata(from workout: HKWorkout) -> WorkoutExportMetadata {
        var name: String?
        if let brand = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String {
            name = brand
        }

        return WorkoutExportMetadata(
            id: workout.uuid.uuidString,
            startDate: isoFormatter.string(from: workout.startDate),
            endDate: isoFormatter.string(from: workout.endDate),
            durationSeconds: workout.duration,
            activityType: WorkoutActivityTypeFormatter.name(for: workout.workoutActivityType),
            activityTypeRaw: workout.workoutActivityType.rawValue,
            totalDistanceMetres: workout.totalDistance?.doubleValue(for: .meter()),
            totalEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
            name: name,
            source: workout.sourceRevision.source.name
        )
    }

    static func summary(from workout: HKWorkout) -> WorkoutSummary {
        WorkoutSummary(
            id: workout.uuid,
            activityType: WorkoutActivityTypeFormatter.name(for: workout.workoutActivityType),
            startDate: workout.startDate,
            durationSeconds: workout.duration,
            totalDistanceMetres: workout.totalDistance?.doubleValue(for: .meter()),
            totalEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        )
    }

    static func metrics(from raw: [String: Any]) -> WorkoutExportMetrics {
        WorkoutExportMetrics(
            heartRate: parseMetricSeries(raw["heart_rate"]),
            runningPower: parseMetricSeries(raw["running_power"]),
            runningSpeed: parseMetricSeries(raw["running_speed"]),
            strideLength: parseMetricSeries(raw["stride_length"]),
            verticalOscillation: parseMetricSeries(raw["vertical_oscillation"]),
            groundContactTime: parseMetricSeries(raw["ground_contact_time"]),
            route: parseRoute(raw["route"])
        )
    }

    static func encodeJSON(_ envelope: WorkoutExportEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    private static func parseMetricSeries(_ value: Any?) -> [MetricDataPoint]? {
        guard let rows = value as? [[String: Any]], !rows.isEmpty else { return nil }
        let points = rows.compactMap { row -> MetricDataPoint? in
            guard let timestamp = row["timestamp"] as? Double,
                let date = row["date"] as? String,
                let sampleValue = row["value"] as? Double
            else { return nil }
            return MetricDataPoint(timestamp: timestamp, date: date, value: sampleValue)
        }
        return points.isEmpty ? nil : points
    }

    private static func parseRoute(_ value: Any?) -> [RouteDataPoint]? {
        guard let rows = value as? [[String: Any]], !rows.isEmpty else { return nil }
        let points = rows.compactMap { row -> RouteDataPoint? in
            guard let latitude = row["latitude"] as? Double,
                let longitude = row["longitude"] as? Double,
                let altitude = row["altitude"] as? Double,
                let timestamp = row["timestamp"] as? Double,
                let date = row["date"] as? String,
                let horizontalAccuracy = row["horizontal_accuracy"] as? Double,
                let verticalAccuracy = row["vertical_accuracy"] as? Double,
                let speed = row["speed"] as? Double,
                let course = row["course"] as? Double
            else { return nil }
            return RouteDataPoint(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                timestamp: timestamp,
                date: date,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                speed: speed,
                course: course
            )
        }
        return points.isEmpty ? nil : points
    }
}

enum WorkoutActivityTypeFormatter {
    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "strength_training"
        case .traditionalStrengthTraining: return "strength_training"
        case .crossTraining: return "cross_training"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stair_climbing"
        case .highIntensityIntervalTraining: return "hiit"
        case .jumpRope: return "jump_rope"
        case .pilates: return "pilates"
        case .dance: return "dance"
        case .cooldown: return "cooldown"
        case .coreTraining: return "core_training"
        default: return "other_\(type.rawValue)"
        }
    }
}
