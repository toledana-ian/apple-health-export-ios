import AppIntents

struct HealthExportShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PushLatestWorkoutIntent(),
            phrases: [
                "Push my latest workout with \(.applicationName)",
                "Export my workout with \(.applicationName)",
                "Send my workout with \(.applicationName)",
            ],
            shortTitle: "Push Latest Workout",
            systemImageName: "square.and.arrow.up"
        )
    }
}
