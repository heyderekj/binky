import AppIntents
import AppKit
import Foundation

// Siri, Spotlight and Shortcuts actions beyond "Sort Files". They run inside the app and reuse
// the same paths as the menu bar, so Apple Intelligence can chain them like any other action.

// MARK: - Routine entity

struct RoutineEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Routine", comment: "Shortcuts: routine entity type name.")
    )
    static var defaultQuery = RoutineQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static func enabled() -> [RoutineEntity] {
        BinkyMenuBarController.enabledRoutinesFromDefaults().map {
            RoutineEntity(id: $0.id, title: BinkyMenuBarController.menuBarRoutineDisplayTitle($0))
        }
    }
}

struct RoutineQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [RoutineEntity] {
        RoutineEntity.enabled().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        RoutineEntity.enabled()
    }

    func entities(matching string: String) async throws -> [RoutineEntity] {
        RoutineEntity.enabled().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
}

// MARK: - Sort

struct SortRoutineIntent: AppIntent {
    static var title = LocalizedStringResource("Sort Now", comment: "Shortcuts: sort a routine's folder now.")
    static var description = IntentDescription(
        LocalizedStringResource(
            "Sorts one routine's folder, or every routine when none is picked.",
            comment: "Shortcuts: Sort Now intent description."
        )
    )

    @Parameter(title: LocalizedStringResource("Routine", comment: "Shortcuts: routine parameter."))
    var routine: RoutineEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Sort \(\.$routine) with Binky")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingWindowRequest.post(.sort(routineID: routine?.id))
        // Nobody took it: the organizer window isn't open, so open it and it runs on appear.
        if PendingWindowRequest.hasPending {
            NSApp.activate()
            NotificationCenter.default.post(name: .binkyShowMainWindow, object: nil)
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("Sh. Binky’s handling it.", comment: "Siri reply after starting a sort.")))
    }
}

// MARK: - Undo

struct UndoLastSortIntent: AppIntent {
    static var title = LocalizedStringResource("Undo Last Sort", comment: "Shortcuts: undo the most recent sort.")
    static var description = IntentDescription(
        LocalizedStringResource(
            "Puts the files from Binky's most recent sort back where they were.",
            comment: "Shortcuts: Undo Last Sort intent description."
        )
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if DownloadsSortOrchestrator.shared.isSorting {
            return .result(dialog: IntentDialog(LocalizedStringResource("Binky’s mid-sort. Try again in a moment.", comment: "Siri reply: undo refused while sorting.")))
        }
        guard let record = BinkyPrefsStore().loadSessionHistory().first,
              let blob = record.batchSummaryData,
              let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: blob),
              !outcome.reversibleMoves.isEmpty else {
            return .result(dialog: IntentDialog(LocalizedStringResource("Nothing to undo.", comment: "Siri reply: no sort to undo.")))
        }

        let moves = outcome.reversibleMoves
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(LocalizedStringResource(
                "Put \(moves.count) files back where they were?",
                comment: "Siri confirmation before undoing a sort; integer file count."
            )))
        )

        let summary = await DownloadsSortOrchestrator.shared.undoMovesReversingSort(
            moves.map { (destination: $0.destination, source: $0.source) },
            clearPinnedUndoIfOutcomeID: outcome.id
        )
        let putBack = summary.attempted - summary.failures
        if summary.failures > 0 {
            return .result(dialog: IntentDialog(LocalizedStringResource(
                "Put back \(putBack). \(summary.failures) had already moved on.",
                comment: "Siri reply after a partial undo; files restored, then files that were no longer there."
            )))
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(
            "Put back \(putBack) files.",
            comment: "Siri reply after undoing a sort; integer file count."
        )))
    }
}

// MARK: - Review

struct ReviewStatusIntent: AppIntent {
    static var title = LocalizedStringResource("Check Review", comment: "Shortcuts: how many files wait in Review.")
    static var description = IntentDescription(
        LocalizedStringResource(
            "Tells you how many files are waiting in the Review folder.",
            comment: "Shortcuts: Check Review intent description."
        )
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let count = BinkyPreferences.current?.reviewFolderItemCount() ?? 0
        if count == 0 {
            return .result(value: 0, dialog: IntentDialog(LocalizedStringResource("Review’s empty. All calm.", comment: "Siri reply: nothing in Review.")))
        }
        return .result(
            value: count,
            dialog: IntentDialog(LocalizedStringResource("\(count) want a second look.", comment: "Review popover subtitle."))
        )
    }
}

struct TidyReviewIntent: AppIntent {
    static var title = LocalizedStringResource("Tidy Review", comment: "Shortcuts: open the Review triage sheet.")
    static var description = IntentDescription(
        LocalizedStringResource(
            "Opens Binky's Review folder so you can place what it couldn't.",
            comment: "Shortcuts: Tidy Review intent description."
        )
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingWindowRequest.post(.reviewTriage)
        NSApp.activate()
        NotificationCenter.default.post(name: .binkyShowMainWindow, object: nil)
        return .result()
    }
}
