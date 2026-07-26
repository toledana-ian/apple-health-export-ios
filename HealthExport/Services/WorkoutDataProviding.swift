import Foundation
import HealthKit

@MainActor
protocol WorkoutDataProviding: AnyObject {
    var isAuthorised: Bool { get }
    func fetchWorkouts(limit: Int) async throws -> [HKWorkout]
    func fetchAllMetrics(for workout: HKWorkout) async throws -> [String: Any]
}

extension HealthKitManager: WorkoutDataProviding {}
