import AppKit
import SwiftUI

/// In-app triage for files sitting in **Review** (origin hints, move, rule, trash).
struct ReviewFolderTriageSheet: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ReviewTriageItem] = []
    @State private var ruleEditor: RuleEditorSheetState?
    /// Apple Intelligence guesses, filled in one file at a time after the list appears.
    @State private var suggestions: [URL: ReviewSuggestion] = [:]
    @State private var habit: ReviewHabits.Habit?

    private static let moveTargets: [FileSortCategory] = [
        .images, .pdf, .video, .audio, .documents, .archives, .apps, .screenshots, .misc, .folders, .receipts,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "Still figuring these out.", comment: "Review triage sheet title."))
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Button(String(localized: "Done", comment: "Dismiss sheet.")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text(String(localized: "Files in Review didn’t match a rule. Move them, teach Binky a new rule, or trash.", comment: "Review triage subtitle."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let habit {
                habitBanner(habit)
            }

            if items.isEmpty {
                Text(String(localized: "Nothing in Review. Binky’s on top of it.", comment: "Review triage empty."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.tertiary)
            } else {
                List {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.name)
                                .font(.headline)
                                .lineLimit(2)
                            if let host = item.originHost, !host.isEmpty {
                                Text(String.localizedStringWithFormat(String(localized: "From %@.", comment: "Review row origin."), host))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let suggestion = suggestions[item.url] {
                                Label {
                                    Text(String(
                                        localized: "\(suggestion.reason) → \(suggestion.destinationRelativePath)",
                                        comment: "Review row: Apple Intelligence guess, e.g. 'Looks like a tax form → Finance/Taxes'."
                                    ))
                                } icon: {
                                    Image(systemName: "sparkles")
                                }
                                .font(.caption)
                                .foregroundStyle(binkyTintColor)
                                .lineLimit(1)
                            }
                            HStack(spacing: 8) {
                                if let suggestion = suggestions[item.url] {
                                    Button(String(
                                        localized: "Move to \((suggestion.destinationRelativePath as NSString).lastPathComponent)",
                                        comment: "Review triage: accept the suggested folder; folder name interpolated."
                                    )) {
                                        moveItem(item, toRelativePath: suggestion.destinationRelativePath)
                                    }
                                    .glassProminentButton()
                                    .tint(binkyTintColor)
                                    .controlSize(.small)
                                }

                                Menu(String(localized: "Move to…", comment: "Review triage move menu.")) {
                                    ForEach(Self.moveTargets, id: \.rawValue) { cat in
                                        Button(Self.destinationMenuLabel(for: cat)) {
                                            moveItem(item, to: cat)
                                        }
                                    }
                                }
                                .controlSize(.small)

                                Button(String(localized: "Make a rule…", comment: "Review triage new rule.")) {
                                    let order = prefs.sortRoutingRules.count + 1
                                    var draft = SortRule.draftFromReviewFile(url: item.url, order: order)
                                    if let suggestion = suggestions[item.url] {
                                        draft.destinationRelativePath = suggestion.destinationRelativePath
                                    }
                                    ruleEditor = RuleEditorSheetState(draft: draft, isNew: true)
                                }
                                .controlSize(.small)

                                Button(String(localized: "Trash", comment: "Review triage trash."), role: .destructive) {
                                    trashItem(item)
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minHeight: 240)
            }
        }
        .padding(22)
        .frame(minWidth: 480, minHeight: 380)
        .onAppear {
            reloadItems()
            refreshHabit()
        }
        .task(id: items.map(\.url)) {
            await suggestDestinations()
        }
        .sheet(item: $ruleEditor) { state in
            RuleEditorSheet(
                state: state,
                onCancel: { ruleEditor = nil },
                onSave: { saved in
                    prefs.sortRoutingRules.append(saved)
                    prefs.sortCustomRulesEnabled = true
                    ruleEditor = nil
                    refreshHabit()
                }
            )
            .environmentObject(prefs)
        }
    }

    private func reviewDirectoryURL() -> URL {
        let root = prefs.activeSortSweepRootDirectory()
        return root.appendingPathComponent(FileSortCategory.review.downloadsSubfolder, isDirectory: true)
    }

    private func reloadItems() {
        let dir = reviewDirectoryURL()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            items = []
            return
        }
        items = urls.compactMap { url -> ReviewTriageItem? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false else { return nil }
            let host = WhereFromsReader.primaryOriginHost(forFileAt: url)
            return ReviewTriageItem(id: UUID(), url: url, name: url.lastPathComponent, originHost: host)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func moveItem(_ item: ReviewTriageItem, to category: FileSortCategory) {
        moveItem(item, toRelativePath: category.downloadsSubfolder)
    }

    private func moveItem(_ item: ReviewTriageItem, toRelativePath relativePath: String) {
        let root = prefs.activeSortSweepRootDirectory()
        let destDir = root.appendingPathComponent(relativePath, isDirectory: true)
        let dest = DownloadsSortOrchestrator.uniquify(
            destinationDirectory: destDir,
            preferredFilename: item.url.lastPathComponent
        )
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: item.url, to: dest)
            ReviewHabits.record(originHost: item.originHost, ext: item.url.pathExtension, destination: relativePath)
            reloadItems()
            refreshHabit()
        } catch {
            NSSound.beep()
        }
    }

    private func trashItem(_ item: ReviewTriageItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            reloadItems()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Apple Intelligence

    private func suggestDestinations() async {
        guard FileUnderstanding.isModelAvailable, !items.isEmpty else { return }
        let root = prefs.activeSortSweepRootDirectory()
        let folders = await Task.detached {
            FileUnderstanding.relativeDirectoryPaths(under: root, maxDepth: 3, maxItems: 120)
        }.value
        for item in items where suggestions[item.url] == nil {
            guard !Task.isCancelled else { return }
            if let suggestion = await FileUnderstanding.suggestDestination(
                for: item.url,
                originHost: item.originHost,
                existingFolders: folders
            ) {
                suggestions[item.url] = suggestion
            }
        }
    }

    // MARK: - Habits → rules

    private func refreshHabit() {
        habit = ReviewHabits.strongestHabit(existingRules: prefs.sortRoutingRules)
    }

    private func habitBanner(_ habit: ReviewHabits.Habit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(binkyTintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Noticed a habit.", comment: "Review triage: banner title when a repeat move pattern is found."))
                    .font(.subheadline.weight(.semibold))
                Text(habit.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Make it a rule…", comment: "Review triage: turn a repeat move pattern into a rule.")) {
                Task { await openRuleEditor(for: habit) }
            }
            .glassProminentButton()
            .tint(binkyTintColor)
            .controlSize(.small)
            Button(String(localized: "Not now", comment: "Review triage: dismiss the habit suggestion.")) {
                ReviewHabits.dismiss(habit)
                refreshHabit()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    /// The model names the rule from a plain phrase; the matching itself comes from what was observed.
    private func openRuleEditor(for habit: ReviewHabits.Habit) async {
        let order = prefs.sortRoutingRules.count + 1
        var draft = await RuleSynthesizer.synthesize(from: habit.phrase, order: order) ?? SortRule.fresh(order: order)
        draft.originDomains = habit.originHost.map { [$0] } ?? []
        draft.matchExtensions = habit.ext.map { [$0] } ?? []
        draft.destinationRelativePath = habit.destination
        draft.fileKindFilter = .any
        draft.contentMatch = .disabled
        if !FileUnderstanding.isModelAvailable || draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.name = habit.ruleName
        }
        ruleEditor = RuleEditorSheetState(draft: draft, isNew: true)
    }

    private static func destinationMenuLabel(for category: FileSortCategory) -> String {
        switch category {
        case .images: return String(localized: "Images", comment: "Sort category.")
        case .pdf: return String(localized: "PDF", comment: "Sort category.")
        case .video: return String(localized: "Video", comment: "Sort category.")
        case .audio: return String(localized: "Audio", comment: "Sort category.")
        case .documents: return String(localized: "Documents", comment: "Sort category.")
        case .archives: return String(localized: "Archives", comment: "Sort category.")
        case .apps: return String(localized: "Apps / installers", comment: "Sort category.")
        case .screenshots: return String(localized: "Screenshots", comment: "Sort category.")
        case .misc: return String(localized: "Misc", comment: "Sort category.")
        case .review: return String(localized: "Review", comment: "Sort category.")
        case .duplicates: return String(localized: "Duplicates", comment: "Sort category.")
        case .receipts: return String(localized: "Receipts", comment: "Sort category.")
        case .folders: return String(localized: "Folders", comment: "Sort category.")
        }
    }

    struct ReviewTriageItem: Identifiable {
        let id: UUID
        let url: URL
        let name: String
        let originHost: String?
    }
}

// MARK: - Review habits

/// Remembers where Review files get moved by hand, so a repeat can become a rule.
enum ReviewHabits {
    struct Move: Codable {
        var host: String?
        var ext: String
        var destination: String
        var date: Date
    }

    struct Habit: Equatable {
        let originHost: String?
        let ext: String?
        let destination: String

        var key: String { "\(originHost ?? "")|\(ext ?? "")|\(destination)" }

        var summary: String {
            if let originHost {
                return String(
                    localized: "Files from \(originHost) keep going to \(destination).",
                    comment: "Review triage habit banner; site, then folder path."
                )
            }
            return String(
                localized: ".\(ext ?? "") files keep going to \(destination).",
                comment: "Review triage habit banner; file extension, then folder path."
            )
        }

        /// Plain English for the rule synthesizer, which names the rule.
        var phrase: String {
            if let originHost { return "files from \(originHost) to \(destination)" }
            return ".\(ext ?? "") files to \(destination)"
        }

        var ruleName: String {
            let folder = (destination as NSString).lastPathComponent
            return "\(originHost ?? "." + (ext ?? "")) → \(folder)"
        }
    }

    private static let logKey = "review.habitLog"
    private static let dismissedKey = "review.habitDismissed"
    private static let maxLog = 60

    static func record(originHost: String?, ext: String, destination: String) {
        var log = loadLog()
        let host = originHost?.trimmingCharacters(in: .whitespaces).lowercased()
        log.append(Move(
            host: host?.isEmpty == false ? host : nil,
            ext: ext.lowercased(),
            destination: destination,
            date: Date()
        ))
        if log.count > maxLog { log.removeFirst(log.count - maxLog) }
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }

    /// Same site → same folder twice, or same file type → same folder three times,
    /// with no rule already doing it and not dismissed.
    static func strongestHabit(existingRules: [SortRule]) -> Habit? {
        let log = loadLog()
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])

        func covered(_ habit: Habit) -> Bool {
            existingRules.contains { rule in
                guard rule.isEnabled, rule.destinationRelativePath == habit.destination else { return false }
                if let host = habit.originHost { return rule.originDomains.contains { $0.lowercased() == host } }
                if let ext = habit.ext { return rule.matchExtensions.contains(ext) }
                return false
            }
        }

        func best(_ candidates: [Habit: Int], minimum: Int) -> Habit? {
            candidates
                .filter { $0.value >= minimum && !dismissed.contains($0.key.key) && !covered($0.key) }
                .max { $0.value < $1.value }?
                .key
        }

        var byHost: [Habit: Int] = [:]
        var byExt: [Habit: Int] = [:]
        for move in log {
            if let host = move.host {
                byHost[Habit(originHost: host, ext: nil, destination: move.destination), default: 0] += 1
            } else if !move.ext.isEmpty {
                byExt[Habit(originHost: nil, ext: move.ext, destination: move.destination), default: 0] += 1
            }
        }
        return best(byHost, minimum: 2) ?? best(byExt, minimum: 3)
    }

    static func dismiss(_ habit: Habit) {
        var dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        dismissed.append(habit.key)
        UserDefaults.standard.set(dismissed, forKey: dismissedKey)
    }

    private static func loadLog() -> [Move] {
        guard let data = UserDefaults.standard.data(forKey: logKey) else { return [] }
        return (try? JSONDecoder().decode([Move].self, from: data)) ?? []
    }
}

extension ReviewHabits.Habit: Hashable {}

