import SwiftUI

struct PushLatestWorkoutSection: View {
    @ObservedObject var serverStore: ServerStore
    @ObservedObject var healthKitManager: HealthKitManager

    @State private var isPushing = false
    @State private var pushSummary: WorkoutPushBatchSummary?
    @State private var pushError: String?

    private var exportService: WorkoutExportService {
        WorkoutExportService(healthKitManager: healthKitManager, serverStore: serverStore)
    }

    private var enabledServerCount: Int {
        serverStore.enabledServers.count
    }

    private var canPush: Bool {
        healthKitManager.isAuthorised && enabledServerCount > 0 && !isPushing
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task { await pushLatestWorkout() }
                } label: {
                    HStack {
                        Spacer()
                        if isPushing {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Pushing Latest Workout…")
                        } else {
                            Label(
                                "Push Latest Workout to All Servers",
                                systemImage: "square.and.arrow.up"
                            )
                            .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canPush)

                if !healthKitManager.isAuthorised {
                    Text("Authorise HealthKit before pushing workouts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if enabledServerCount == 0 {
                    Text("Add and enable at least one destination server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Delivers your most recent workout to \(enabledServerCount) enabled server(s).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let pushError {
                    Text(pushError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let pushSummary {
                    PushResultSummaryView(summary: pushSummary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Quick Export")
        }
    }

    private func pushLatestWorkout() async {
        isPushing = true
        pushError = nil
        pushSummary = nil
        defer { isPushing = false }

        do {
            pushSummary = try await exportService.pushLatestWorkout(
                to: serverStore.servers,
                secretProvider: { serverStore.secret(for: $0) }
            )
        } catch {
            pushError = error.localizedDescription
        }
    }
}

struct PushResultSummaryView: View {
    let summary: WorkoutPushBatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.summaryText)
                .font(.subheadline)
                .foregroundStyle(summary.allSucceeded ? .green : .primary)

            ForEach(summary.workoutResults) { result in
                HStack(alignment: .top) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.serverName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(result.outcomeSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
