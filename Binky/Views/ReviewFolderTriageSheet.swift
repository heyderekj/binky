import AppKit
import SwiftUI

/// In-app triage for files sitting in **Review** (origin hints, move, rule, trash).
struct ReviewFolderTriageSheet: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ReviewTriageItem] = []
    @State private var ruleEditor: RuleEditorSheetState?
    /// Surfaced when a Review-folder action (move / trash) fails. Previously we only beeped, which
    /// gave zero feedback to users on muted machines or with VoiceOver expecting an announcement.
    @State private var errorMessage: String?

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
                            HStack(spacing: 8) {
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
                                    ruleEditor = RuleEditorSheetState(
                                        draft: SortRule.draftFromReviewFile(url: item.url, order: order),
                                        isNew: true
                                    )
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
        .onAppear { reloadItems() }
        .alert(
            String(localized: "Couldn’t finish that.", comment: "Review triage error alert title."),
            isPresented: errorAlertBinding,
            presenting: errorMessage
        ) { _ in
            Button(String(localized: "OK", comment: "Dismiss alert.")) { errorMessage = nil }
                .keyboardShortcut(.defaultAction)
        } message: { detail in
            Text(detail)
        }
        .sheet(item: $ruleEditor) { state in
            RuleEditorSheet(
                state: state,
                onCancel: { ruleEditor = nil },
                onSave: { saved in
                    prefs.sortRoutingRules.append(saved)
                    prefs.sortCustomRulesEnabled = true
                    ruleEditor = nil
                }
            )
            .environmentObject(prefs)
        }
    }

    /// Bridges an optional `errorMessage` to a `Bool` binding for SwiftUI's `.alert(isPresented:)`.
    /// Setting it back to `false` clears the message so the alert can re-present after future failures.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in if !newValue { errorMessage = nil } }
        )
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
        let root = prefs.activeSortSweepRootDirectory()
        let destDir = StarterDestinations.directory(for: category, root: root)
        let dest = DownloadsSortOrchestrator.uniquify(
            destinationDirectory: destDir,
            preferredFilename: item.url.lastPathComponent
        )
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: item.url, to: dest)
            reloadItems()
        } catch {
            NSSound.beep()
            // Sound alone doesn't help muted Macs or VoiceOver. Show a localized error message
            // so the user knows *what* failed, not just that *something* did.
            errorMessage = String.localizedStringWithFormat(
                String(localized: "Couldn’t move “%1$@”: %2$@", comment: "Review triage move-failure detail (filename, system error)."),
                item.name,
                error.localizedDescription
            )
        }
    }

    private func trashItem(_ item: ReviewTriageItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            reloadItems()
        } catch {
            NSSound.beep()
            errorMessage = String.localizedStringWithFormat(
                String(localized: "Couldn’t move “%1$@” to the Trash: %2$@", comment: "Review triage trash-failure detail (filename, system error)."),
                item.name,
                error.localizedDescription
            )
        }
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
