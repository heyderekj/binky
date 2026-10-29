import AppIntents

/// Surfaces Binky’s Shortcuts actions in the Shortcuts app’s suggestions.
struct BinkyAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SortFilesWithBinkyIntent(),
            phrases: [
                "Sort files with \(.applicationName)",
                "Organize downloads with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Sort Files", comment: "Shortcuts: suggested action short title."),
            systemImageName: "folder"
        )
        AppShortcut(
            intent: SortRoutineIntent(),
            phrases: [
                "Sort \(\.$routine) with \(.applicationName)",
                "Sort now with \(.applicationName)",
                "Calm my folders with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Sort Now", comment: "Shortcuts: suggested action short title."),
            systemImageName: "tray.and.arrow.down"
        )
        AppShortcut(
            intent: UndoLastSortIntent(),
            phrases: [
                "Undo the last \(.applicationName) sort",
                "Undo \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Undo Last Sort", comment: "Shortcuts: suggested action short title."),
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: ReviewStatusIntent(),
            phrases: [
                "What’s in \(.applicationName) Review",
                "Check \(.applicationName) Review",
            ],
            shortTitle: LocalizedStringResource("Check Review", comment: "Shortcuts: suggested action short title."),
            systemImageName: "folder.badge.questionmark"
        )
        AppShortcut(
            intent: TidyReviewIntent(),
            phrases: [
                "Tidy \(.applicationName) Review",
            ],
            shortTitle: LocalizedStringResource("Tidy Review", comment: "Shortcuts: suggested action short title."),
            systemImageName: "tray.full"
        )
    }
}
