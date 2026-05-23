import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main View

struct DailyCalmPreviewSheet: View {
    @EnvironmentObject var prefs: BinkyPreferences

    // Sources
    @AppStorage("binky.v2.sources") private var sourcesData: Data = Data()
    @State private var sources: [URL] = []
    @State private var includeSubfolders: Bool = true

    // Results
    @State private var items: [FileItem] = []
    @State private var isScanning: Bool = false
    @State private var scanTotal: Int = 0
    @State private var scanProgress: Int = 0
    @State private var scanTask: Task<Void, Never>? = nil

    // Stats
    @State private var filedCount: Int = 0
    @State private var skippedCount: Int = 0

    // Undo
    @State private var lastAction: UndoAction? = nil
    @State private var showUndoToast: Bool = false

    // Navigation
    @State private var selectedIndex: Int = 0
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            mainContent
            Divider()
            bottomBar
        }
        .frame(minWidth: 600, minHeight: 480)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay(dropOverlay)
        .overlay(undoToast, alignment: .bottom)
        .task { loadSources(); if !sources.isEmpty { startScan() } }
        .onDisappear { saveSources() }
        .background(keyboardHandler)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            if isScanning {
                ProgressView(value: Double(scanProgress), total: max(Double(scanTotal), 1))
                    .frame(width: 100)
                Text("Scanning \(scanProgress)/\(scanTotal)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Stop") { stopScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if !items.isEmpty {
                Label("\(filedCount) filed", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                Label("\(skippedCount) skipped", systemImage: "forward.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(remainingCount) remaining", systemImage: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(remainingCount > 0 ? Color.primary : Color.green)
            }

            Spacer()

            if !isScanning && remainingCount > 0 && highConfidenceCount > 3 {
                Button("Apply \(highConfidenceCount) confident") {
                    applyHighConfidence()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(binkyTintColor)
            }

            Button { startScan() } label: {
                Label("Scan", systemImage: "arrow.clockwise")
            }
            .disabled(sources.isEmpty || isScanning)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if sources.isEmpty {
            emptyState
        } else if items.isEmpty && !isScanning {
            allClearState
        } else {
            fileList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Drop folders here to get started")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Add folder") { addSource() }
                    .buttonStyle(.borderedProminent)
                Button("Add files") { addFiles() }
                    .buttonStyle(.bordered)
            }
            Text("or drag folders / files onto this window")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var allClearState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("All clear.")
                .font(.title2.bold())
            if filedCount > 0 {
                Text("You filed \(filedCount) file(s) this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            List(selection: Binding(
                get: { items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil },
                set: { id in if let idx = items.firstIndex(where: { $0.id == id }) { selectedIndex = idx } }
            )) {
                // Sources summary (collapsible)
                Section {
                    ForEach(sources, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.tint)
                                .font(.caption)
                            Text(shortenPath(url.path))
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button { sources.removeAll { $0 == url }; saveSources() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button("+ Folder") { addSource() }.buttonStyle(.borderless).font(.caption)
                        Toggle("Subfolders", isOn: $includeSubfolders).font(.caption)
                    }
                } header: {
                    Text("Sources").font(.caption.bold())
                }

                // File items
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        FileRow(
                            item: binding(for: idx),
                            onApply: { dest in applyItem(at: idx, to: dest) },
                            onSkip: { skipItem(at: idx) },
                            onOther: { pickOther(for: idx) },
                            isSelected: idx == selectedIndex
                        )
                        .id(item.id)
                    }
                } header: {
                    Text("\(remainingCount) files to review").font(.caption.bold())
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: selectedIndex) { _, newIdx in
                if items.indices.contains(newIdx) {
                    proxy.scrollTo(items[newIdx].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text("⏎ Apply top · ⌫ Skip · ⌘⏎ Apply all confident · ↑↓ Navigate")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if let action = lastAction, showUndoToast {
                Text("Moved \(action.filename)")
                    .font(.caption)
                Button("Undo") { undoLast() }
                    .buttonStyle(.borderless)
                    .font(.caption.bold())
                    .foregroundStyle(binkyTintColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Overlays

    @ViewBuilder private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .background(Color.accentColor.opacity(0.05).clipShape(RoundedRectangle(cornerRadius: 12)))
                .overlay(Label("Drop to add", systemImage: "plus.circle.fill").font(.title3).foregroundStyle(.tint))
                .padding(8)
        }
    }

    @ViewBuilder private var undoToast: some View {
        EmptyView() // Undo is shown inline in bottomBar
    }

    // MARK: - Keyboard

    private var keyboardHandler: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onKeyPress(.return) { handleReturn(); return .handled }
            .onKeyPress(.delete) { handleDelete(); return .handled }
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
    }

    private func handleReturn() {
        if NSEvent.modifierFlags.contains(.command) {
            applyHighConfidence()
        } else {
            applyCurrentTop()
        }
    }

    private func handleDelete() {
        skipCurrent()
    }

    private func moveSelection(_ delta: Int) {
        let next = selectedIndex + delta
        if items.indices.contains(next) { selectedIndex = next }
    }

    // MARK: - Actions

    @MainActor
    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        items.removeAll()
        scanProgress = 0
        filedCount = 0
        skippedCount = 0

        let allFiles = collectFiles()
        scanTotal = allFiles.count

        let fallbackRoot = sources.first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let predictor = DestinationPredictor(fallbackRoot: fallbackRoot)
        let resolver: InboxRootResolver = { cat in fallbackRoot.appendingPathComponent(cat.downloadsSubfolder, isDirectory: true) }
        let adapter = HeuristicSuggestionAdapter(inboxRoot: resolver, predictor: predictor)
        let classifyStage = ClassifyStage()
        let originStage = OriginHostStage()
        let store = SuggestionStore.shared
        let ctx = PipelineContext()

        for url in allFiles {
            guard !Task.isCancelled else { break }
            scanProgress += 1
            // Yield to let the main actor process UI events (Stop button).
            await Task.yield()

            let classified = try? await classifyStage.run(url, context: ctx)
            let hosts = try? await originStage.run(url, context: ctx)
            guard let classified, let hosts else { continue }

            let ingested = IngestedFile(url: url, classification: classified, originHosts: hosts, hashed: nil)
            let suggestions = (try? await adapter.suggest(for: ingested, context: ctx)) ?? []

            // Filter already-decided
            let pending = suggestions.filter { store.decision(for: $0) == nil }
            guard !pending.isEmpty else { continue }

            let item = FileItem(
                url: url,
                category: classified.category,
                originHost: hosts.primary,
                candidates: pending
            )
            items.append(item)
        }

        isScanning = false
        selectedIndex = 0
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func startScan() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    private func applyItem(at idx: Int, to suggestion: Suggestion) {
        guard items.indices.contains(idx) else { return }
        let executor = SuggestionExecutor()
        let result = executor.execute(suggestion)
        switch result.outcome {
        case .success(let path):
            items[idx].state = .filed(path ?? "")
            filedCount += 1
            SuggestionStore.shared.record(suggestion, decision: .accepted)
            lastAction = UndoAction(source: suggestion.source, destination: URL(fileURLWithPath: path ?? ""), filename: suggestion.source.lastPathComponent)
            showUndoToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { showUndoToast = false }
            advanceSelection()
        case .kept:
            items[idx].state = .filed("(kept)")
            filedCount += 1
            advanceSelection()
        case .failure(let reason):
            items[idx].state = .error(reason)
        }
    }

    private func skipItem(at idx: Int) {
        guard items.indices.contains(idx) else { return }
        items[idx].state = .skipped
        skippedCount += 1
        if let s = items[idx].candidates.first {
            SuggestionStore.shared.record(s, decision: .snoozed)
        }
        advanceSelection()
    }

    private func applyCurrentTop() {
        guard items.indices.contains(selectedIndex),
              items[selectedIndex].state == .pending,
              let top = items[selectedIndex].candidates.first else { return }
        applyItem(at: selectedIndex, to: top)
    }

    private func skipCurrent() {
        guard items.indices.contains(selectedIndex), items[selectedIndex].state == .pending else { return }
        skipItem(at: selectedIndex)
    }

    private func applyHighConfidence() {
        let executor = SuggestionExecutor()
        for i in items.indices {
            guard items[i].state == .pending,
                  let top = items[i].candidates.first,
                  (top.confidence ?? 0) >= 0.7 else { continue }
            let result = executor.execute(top)
            if result.succeeded {
                items[i].state = .filed("")
                filedCount += 1
                SuggestionStore.shared.record(top, decision: .accepted)
            }
        }
    }

    private func undoLast() {
        guard let action = lastAction else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: action.destination.path) {
            try? fm.moveItem(at: action.destination, to: action.source)
            // Revert the item state
            if let idx = items.firstIndex(where: { $0.url == action.source }) {
                items[idx].state = .pending
                filedCount = max(0, filedCount - 1)
            }
        }
        showUndoToast = false
        lastAction = nil
    }

    private func advanceSelection() {
        // Move to next pending item
        for i in (selectedIndex + 1)..<items.count {
            if items[i].state == .pending { selectedIndex = i; return }
        }
    }

    private func pickOther(for idx: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Move here"
        if panel.runModal() == .OK, let dest = panel.url {
            let custom = Suggestion(source: items[idx].url, action: .move(to: dest), reasoning: "You chose this folder")
            applyItem(at: idx, to: custom)
        }
    }

    // MARK: - File collection

    private func collectFiles() -> [URL] {
        let fm = FileManager.default
        var all: [URL] = []
        for source in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if includeSubfolders {
                    if let e = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                        for case let url as URL in e {
                            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { all.append(url) }
                        }
                    }
                } else {
                    let entries = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
                    all.append(contentsOf: entries.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true })
                }
            } else {
                all.append(source)
            }
        }
        return all
    }

    // MARK: - Sources persistence

    private func loadSources() {
        if let urls = try? JSONDecoder().decode([String].self, from: sourcesData) {
            sources = urls.map { URL(fileURLWithPath: $0) }
        }
        if sources.isEmpty {
            sources = [prefs.activeSortSweepRootDirectory()]
        }
    }

    private func saveSources() {
        sourcesData = (try? JSONEncoder().encode(sources.map(\.path))) ?? Data()
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        for p in providers {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if !sources.contains(url) { sources.append(url); saveSources() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { startScan() }
    }

    private func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url) { sources.append(url) }
            saveSources()
            startScan()
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url) { sources.append(url) }
            saveSources()
            startScan()
        }
    }

    // MARK: - Helpers

    private var remainingCount: Int { items.filter { $0.state == .pending }.count }
    private var highConfidenceCount: Int {
        items.filter { $0.state == .pending && ($0.candidates.first?.confidence ?? 0) >= 0.7 }.count
    }

    private func binding(for idx: Int) -> Binding<FileItem> {
        Binding(get: { items[idx] }, set: { items[idx] = $0 })
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Models

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let category: FileSortCategory
    let originHost: String?
    let candidates: [Suggestion]
    var state: ItemState = .pending

    enum ItemState: Equatable {
        case pending
        case filed(String)
        case skipped
        case error(String)
    }
}

private struct UndoAction {
    let source: URL
    let destination: URL
    let filename: String
}

// MARK: - File Row

private struct FileRow: View {
    @Binding var item: FileItem
    let onApply: (Suggestion) -> Void
    let onSkip: () -> Void
    let onOther: () -> Void
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Category icon with color
            categoryIcon
                .frame(width: 20)

            // File info
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let host = item.originHost {
                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer()

            // Action area
            switch item.state {
            case .pending:
                pendingActions
            case .filed(let path):
                Label(path.isEmpty ? "Filed" : shortenPath(path), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .skipped:
                Text("Skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    @ViewBuilder
    private var pendingActions: some View {
        if let top = item.candidates.first {
            // Top candidate as primary button
            Button { onApply(top) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                    Text(shortenDest(top))
                        .font(.caption)
                        .lineLimit(1)
                    if let c = top.confidence {
                        Text("\(Int(c * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(binkyTintColor)

            // More candidates in a menu
            if item.candidates.count > 1 {
                Menu {
                    ForEach(item.candidates.dropFirst(), id: \.id) { alt in
                        Button("\(shortenDest(alt)) (\(alt.reasoning))") { onApply(alt) }
                    }
                    Divider()
                    Button("Other…") { onOther() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            } else {
                Button("…") { onOther() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Button { onSkip() } label: {
                Image(systemName: "forward.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Skip (⌫)")
        }
    }

    private var categoryIcon: some View {
        let (name, color) = iconForCategory(item.category)
        return Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(color)
    }

    private func iconForCategory(_ cat: FileSortCategory) -> (String, Color) {
        switch cat {
        case .images, .screenshots: return ("photo.fill", .green)
        case .video: return ("film.fill", .blue)
        case .audio: return ("music.note", .purple)
        case .pdf, .documents: return ("doc.fill", .gray)
        case .archives: return ("archivebox.fill", .orange)
        case .apps: return ("app.fill", .pink)
        case .receipts: return ("dollarsign.circle.fill", .yellow)
        case .duplicates: return ("doc.on.doc.fill", .red)
        case .folders: return ("folder.fill", .cyan)
        case .misc, .review: return ("questionmark.circle.fill", .secondary)
        }
    }

    private func shortenDest(_ s: Suggestion) -> String {
        guard case .move(let dest) = s.action else { return "?" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = dest.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Unused models cleaned up (DestinationMapping, SuggestionCardModel, DuplicateGroup removed)
