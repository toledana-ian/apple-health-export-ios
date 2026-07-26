import AppIntents
import Foundation

struct PushLatestWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Push Latest Workout"
    static var description = IntentDescription(
        "Sends your most recent workout to all enabled destination servers."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let healthKitManager = HealthKitManager()
        await healthKitManager.refreshAuthorisationStatus()
        guard healthKitManager.isAuthorised else {
            throw PushLatestWorkoutIntentError.notAuthorised
        }

        let serverStore = ServerStore()
        guard !serverStore.enabledServers.isEmpty else {
            throw PushLatestWorkoutIntentError.noEnabledServers
        }

        let exportService = WorkoutExportService(
            healthKitManager: healthKitManager,
            serverStore: serverStore
        )

        let summary = try await exportService.pushLatestWorkout(
            to: serverStore.servers,
            secretProvider: { serverStore.secret(for: $0) }
        )

        return .result(dialog: "\(summary.summaryText)")
    }
}

enum PushLatestWorkoutIntentError: LocalizedError {
    case notAuthorised
    case noEnabledServers

    var errorDescription: String? {
        switch self {
        case .notAuthorised:
            return "Open Health Export and authorise HealthKit before running this shortcut."
        case .noEnabledServers:
            return "Add and enable at least one destination server in Health Export."
        }
    }
}
