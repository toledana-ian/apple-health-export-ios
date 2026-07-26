import SwiftUI

struct PushWorkoutsView: View {
    let server: DestinationServer
    @ObservedObject var serverStore: ServerStore
    @ObservedObject var healthKitManager: HealthKitManager

    @State private var workouts: [WorkoutSummary] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var pushMode: WorkoutPushMode = .concurrent
    @State private var isLoading = true
    @State private var isPushing = false
    @State private var loadError: String?
    @State private var pushProgress: (current: Int, total: Int)?
    @State private var pushSummary: WorkoutPushBatchSummary?
    @State private var showingConfirm = false

    private var exportService: WorkoutExportService {
        WorkoutExportService(healthKitManager: healthKitManager, serverStore: serverStore)
    }

    private var currentServer: DestinationServer {
        serverStore.server(id: server.id) ?? server
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading workouts…")
                        Spacer()
                    }
                }
            } else if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            } else if workouts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.run",
                        description: Text("No workouts were found in HealthKit.")
                    )
                }
            } else {
                Section {
                    Picker("Delivery Mode", selection: $pushMode) {
                        ForEach(WorkoutPushMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isPushing)
                } footer: {
                    Text(
                        pushMode == .concurrent
                            ? "All selected workouts are pushed in parallel."
                            : "Workouts are pushed one at a time."
                    )
                }

                Section {
                    ForEach(workouts) { workout in
                        WorkoutSelectionRow(
                            workout: workout,
                            isSelected: selectedIDs.contains(workout.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isPushing else { return }
                            toggleSelection(workout.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Workouts")
                        Spacer()
                        if !selectedIDs.isEmpty {
                            Text("\(selectedIDs.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Showing the 100 most recent workouts, newest first.")
                }
            }

            if isPushing, let progress = pushProgress {
                Section("Progress") {
                    HStack {
                        ProgressView()
                        Text("Pushing workout \(progress.current) of \(progress.total)…")
                            .font(.caption)
                    }
                }
            }

            if let pushSummary {
                Section("Results") {
                    Text(pushSummary.summaryText)
                        .font(.subheadline)
                    ForEach(pushSummary.workoutResults) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.workoutHealthKitUUID.uuidString)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)
                            Text(result.outcomeSummary)
                                .font(.caption)
                                .foregroundStyle(result.success ? .green : .red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Push Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Push") {
                    showingConfirm = true
                }
                .disabled(isPushing || selectedIDs.isEmpty || !currentServer.isEnabled)
            }
        }
        .confirmationDialog(
            "Push \(selectedIDs.count) workout(s) to \(currentServer.name)?",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("Push") {
                Task { await pushSelectedWorkouts() }
            }
        }
        .task {
            await loadWorkouts()
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func loadWorkouts() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            workouts = try await exportService.recentWorkoutSummaries(limit: 100)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func pushSelectedWorkouts() async {
        isPushing = true
        pushSummary = nil
        pushProgress = nil
        defer {
            isPushing = false
            pushProgress = nil
        }

        let orderedIDs = workouts
            .filter { selectedIDs.contains($0.id) }
            .map(\.id)

        do {
            let summary = try await exportService.pushWorkouts(
                ids: orderedIDs,
                to: currentServer,
                mode: pushMode,
                secretProvider: { serverStore.secret(for: $0) },
                onProgress: { current, total in
                    pushProgress = (current, total)
                }
            )
            pushSummary = summary
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct WorkoutSelectionRow: View {
    let workout: WorkoutSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.activityType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                Text(workout.startDate, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(workout.durationFormatted, systemImage: "clock")
                    if let distance = workout.distanceFormatted {
                        Label(distance, systemImage: "figure.run")
                    }
                    if let energy = workout.energyFormatted {
                        Label(energy, systemImage: "flame")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
