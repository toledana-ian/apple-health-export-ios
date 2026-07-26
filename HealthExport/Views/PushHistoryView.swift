import SwiftUI

struct PushHistoryView: View {
    let server: DestinationServer
    @ObservedObject var serverStore: ServerStore

    private var history: [PushHistoryEntry] {
        serverStore.history(for: server.id)
    }

    var body: some View {
        List {
            if history.isEmpty {
                ContentUnavailableView(
                    "No Push History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Workout deliveries to this server will appear here.")
                )
            } else {
                ForEach(history) { entry in
                    PushHistoryRowView(entry: entry)
                }
            }
        }
        .navigationTitle("Push History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PushHistoryRowView: View {
    let entry: PushHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    entry.status.rawValue.capitalized,
                    systemImage: entry.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(entry.status == .success ? .green : .red)
                Spacer()
                Text(entry.timestamp, format: .dateTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let workout = entry.workout {
                Text(workout.summaryLine)
                    .font(.subheadline)
                Text(workout.startDate, format: .dateTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.workoutHealthKitUUID.uuidString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let statusCode = entry.statusCode {
                    Text("HTTP \(statusCode)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let pushDuration = entry.pushDurationFormatted {
                    Text("Push \(pushDuration)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = entry.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
