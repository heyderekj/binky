import SwiftUI
import AppKit

/// Shares one `BinkyPreferences` instance between `OrganizerViewModel` and the environment.
@MainActor
private final class BinkyRootModel: ObservableObject {
    let prefs: BinkyPreferences
    let organizerVM: OrganizerViewModel
    /// Retains idle watching when the organizer window closes (menu bar only).
    private let watchLease: WatchSortCoordinator

    init() {
        let p = BinkyPreferences()
        self.prefs = p
        let vm = OrganizerViewModel()
        self.organizerVM = vm
        self.watchLease = WatchSortCoordinator(prefs: p, viewModel: vm)
    }
}

/// `Window` scene id for macOS preferences (unified title bar chrome matches the main window; unlike `Settings`).
private enum BinkyMacPreferencesWindow {
    static let sceneID = "binky-preferences"
}

@main
struct BinkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var root = BinkyRootModel()
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        // Explicit `id` lets the menu bar / hotkey bridge re-open this window via
        // `openWindow(id: "main")` even when ContentView has been unmounted (closed).
        WindowGroup(id: "main") {
            ContentView(vm: root.organizerVM)
                .environmentObject(root.prefs)
                .environmentObject(updater)
                .tint(binkyTintColor)
                // preferring: ["*"] makes this window actively claim all incoming external events,
                // so SwiftUI routes Finder "Open With" to the existing window instead of spawning new ones.
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
                .background(.ultraThinMaterial)        // frosted glass fill
                .background(TransparentWindow())       // makes NSWindow itself see-through
                .adaptiveVisibleWindowToolbarBackground()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 560)
        .commands {
            CommandGroup(after: .newItem) {
                BinkyShortcutCommands(prefs: root.prefs)
            }
            CommandMenu(String(localized: "View mode", comment: "Menu: switch organizer layout.")) {
                if root.prefs.mainWindowModeVisibility.allowsQuickSort {
                    Button(MainWindowMode.quickSort.title) {
                        NotificationCenter.default.post(
                            name: .binkySwitchMainWindowMode,
                            object: nil,
                            userInfo: [BinkyNotificationUserInfoKey.mainWindowModeRaw: MainWindowMode.quickSort.rawValue]
                        )
                    }
                    .keyboardShortcut("1", modifiers: [.command])
                }

                if root.prefs.mainWindowModeVisibility.allowsRoutines {
                    Button(MainWindowMode.routines.title) {
                        NotificationCenter.default.post(
                            name: .binkySwitchMainWindowMode,
                            object: nil,
                            userInfo: [BinkyNotificationUserInfoKey.mainWindowModeRaw: MainWindowMode.routines.rawValue]
                        )
                    }
                    .keyboardShortcut("2", modifiers: [.command])
                }
            }
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About Binky", comment: "Application menu: about panel.")) {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…", comment: "Application menu: check for updates.")) {
                    NotificationCenter.default.post(name: .binkyCheckUpdates, object: nil)
                }
                Button(String(localized: "History…", comment: "Application menu: open sort history.")) {
                    NotificationCenter.default.post(name: .binkyShowHistory, object: nil)
                }
                LastSortSummaryCommands(vm: root.organizerVM)
            }
            // Replace the default Help menu (which triggers the unhelpful
            // "Help isn't available for Binky" alert because we don't ship
            // a `.help` bundle — adding one would add weight, see CLAUDE.md).
            CommandGroup(replacing: .help) {
                HelpMenuCommands(updater: updater)
            }

            // Preferences use a `Window` scene (not `Settings`) so the unified title bar matches
            // the organizer window — navigation title and Back/Forward stay on one line with the traffic lights.
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…", comment: "App menu: open settings.")) {
                    NotificationCenter.default.post(name: .binkyOpenMacPreferences, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window(String(localized: "Settings", comment: "Preferences window title."), id: BinkyMacPreferencesWindow.sceneID) {
            PreferencesView()
                .environmentObject(root.prefs)
                .environmentObject(updater)
                .tint(binkyTintColor)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 560)
        .commandsRemoved()

        // Opened via the Help menu. Single-instance; reuses the same
        // window if it's already on screen.
        Window("Binky Help", id: "help") {
            HelpWindow()
                .environmentObject(root.prefs)
                .tint(binkyTintColor)
        }
        .defaultSize(width: 820, height: 600)
        .commandsRemoved()

        // v2 dry-run preview window — hidden behind the
        // `v2.dailyCalmPreviewEnabled` UserDefaults key so it's invisible to
        // 1.x users by default. Flip with:
        //   defaults write com.binky.app v2.dailyCalmPreviewEnabled -bool true
        // The Help menu only renders the entry point when the flag is on,
        // but the Window scene itself is always defined so `openWindow(id:)`
        // works for testing without restarting the app.
        Window("Daily Calm Preview", id: "daily-calm-preview") {
            DailyCalmPreviewSheet()
                .environmentObject(root.prefs)
                .tint(binkyTintColor)
        }
        .defaultSize(width: 720, height: 600)
        .commandsRemoved()
    }
}

// MARK: - Last batch summary (fixed shortcut)

private struct LastSortSummaryCommands: View {
    @ObservedObject var vm: OrganizerViewModel

    var body: some View {
        Button(String(localized: "Last Sort Summary…", comment: "Application menu: reopen the last sort summary.")) {
            NotificationCenter.default.post(name: .binkyShowLastBatchSummary, object: nil)
        }
        .disabled(vm.lastSortOutcome == nil)
        .keyboardShortcut(BinkyFixedShortcut.showLastBatchSummary.shortcut.swiftUIKeyboardShortcut)
    }
}

// MARK: - File menu shortcuts (user-customizable)

private struct BinkyShortcutCommands: View {
    @ObservedObject var prefs: BinkyPreferences
    // `openWindow` lives in the App's environment and is callable any time the App scene
    // tree is alive — even when no WindowGroup window is currently presented. This is the
    // only reliable path for "Show Binky" after the user has closed the main window.
    @Environment(\.openWindow) private var openWindow

    private var sortNowMenuTitle: String {
        let enabledCount = prefs.savedPresets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return enabledCount > 1
            ? String(localized: "Sort All", comment: "File menu: run sort across every enabled routine.")
            : String(localized: "Sort Now", comment: "File menu: run an immediate sort for the watched folder.")
    }

    var body: some View {
        Button(String(localized: "Open Files…", comment: "File menu: open file picker.")) {
            NotificationCenter.default.post(name: .binkyOpenPanel, object: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .openFiles).swiftUIKeyboardShortcut)

        Button(sortNowMenuTitle) {
            NotificationCenter.default.post(name: .binkyStartSort, object: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .sortNow).swiftUIKeyboardShortcut)
        // Bridges the AppKit menu bar's "Show Binky" / global hotkey into SwiftUI's
        // `openWindow(id:)`. SwiftUI keeps Commands views alive for the full app lifetime
        // (they back the main menu bar), so this `.onReceive` fires whether or not the
        // main window is currently presented. `openWindow(id:)` brings an existing instance
        // forward, or creates a fresh one if the user previously closed the window.
        .onReceive(NotificationCenter.default.publisher(for: .binkyShowMainWindow)) { _ in
            NSApp.activate()
            openWindow(id: "main")
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyOpenMacPreferences)) { _ in
            NSApp.activate()
            openWindow(id: BinkyMacPreferencesWindow.sceneID)
        }
    }
}

// MARK: - Help menu

/// Wrapped in its own view so we can pull `openWindow` out of the environment
/// (CommandGroup closures don't expose environment directly). `updater` is
/// passed in explicitly because environment objects don't reliably propagate
/// into command builders across all macOS versions.
private struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var updater: UpdateChecker

    private static let repoURL = URL(string: "https://github.com/heyderekj/binky")!
    private static let siteURL = URL(string: "https://binkyfiles.com")!
    private static let leaveReviewURL = URL(string: "https://github.com/heyderekj/binky/discussions/new?category=reviews")!

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Release notes for whichever version is more interesting: the available
    /// update if one's been found, otherwise the version the user is on.
    private var releaseNotesURL: URL {
        if let url = updater.releaseURL { return url }
        return URL(string: "https://github.com/heyderekj/binky/releases/tag/v\(currentVersion)")!
    }

    private var versionLabel: String {
        if let newer = updater.availableVersion {
            return String(localized: "Version \(currentVersion) — \(newer) available", comment: "Help menu: version row when an update is available. First argument is current version, second is available version.")
        }
        return String(localized: "Version \(currentVersion)", comment: "Help menu: version row when no update. Argument is current version.")
    }

    var body: some View {
        // `?` requires shift; SwiftUI only fires when the modifier set matches the actual keystroke,
        // so we must declare both. (Bare `.command` shows ⌘? in the menu but never triggers.)
        Button(String(localized: "Binky Help", comment: "Help menu: open help window.")) { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: [.command, .shift])

        Divider()

        // Info row — always disabled. Reflects update state when known.
        Button(versionLabel) {}
            .disabled(true)

        Button(String(localized: "What’s New…", comment: "Help menu: open release notes.")) {
            NSWorkspace.shared.open(releaseNotesURL)
        }
        Button(String(localized: "Check for Updates…", comment: "Help menu: check for updates.")) {
            NotificationCenter.default.post(name: .binkyCheckUpdates, object: nil)
        }

        Divider()

        Button(String(localized: "GitHub Repo", comment: "Help menu: open source repository.")) {
            NSWorkspace.shared.open(Self.repoURL)
        }
        Button(String(localized: "Leave a Review…", comment: "Help menu: open GitHub Discussions reviews category.")) {
            NSWorkspace.shared.open(Self.leaveReviewURL)
        }
        Button(String(localized: "Report a Bug…", comment: "Help menu: report a bug.")) {
            NSWorkspace.shared.open(DiagnosticsReporter.githubIssueURL(title: String(localized: "Bug: ", comment: "Prefill for GitHub issue title.")))
        }
        Button(String(localized: "Give Feedback…", comment: "Help menu: send feedback email.")) {
            NSWorkspace.shared.open(
                DiagnosticsReporter.emailURL(
                    subject: String(localized: "Feedback — Binky v\(currentVersion)", comment: "Email subject for feedback. Argument is app version."),
                    extraBody: "## Feedback\n\n"
                )
            )
        }
        Button(String(localized: "Visit binkyfiles.com", comment: "Help menu: open marketing site.")) {
            NSWorkspace.shared.open(Self.siteURL)
        }
        Button(String(localized: "Email Support…", comment: "Help menu: contact support.")) {
            NSWorkspace.shared.open(
                DiagnosticsReporter.emailURL(
                    subject: String(localized: "Support — Binky v\(currentVersion)", comment: "Email subject for support. Argument is app version."),
                    extraBody: "## How can we help?\n\n"
                )
            )
        }

        // v2: Daily Calm is the main window; the separate preview entry is no
        // longer needed. Kept as a comment so git blame shows the lineage.
    }
}

// MARK: - About panel

/// Opens a standard macOS About window with a custom credits block underneath
/// the app name and version. We show the live bundle size so marketing stays aligned
/// with reality as the bundle evolves, plus clickable links to the site and repo.
private func showAboutPanel() {
    let credits = NSMutableAttributedString()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 2

    let baseAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph
    ]
    var linkAttrs: [NSAttributedString.Key: Any] = baseAttrs
    // Leave .foregroundColor to the system link color so URLs look like links.
    linkAttrs.removeValue(forKey: .foregroundColor)

    credits.append(NSAttributedString(string: bundleSizeString() + "\n", attributes: baseAttrs))

    var siteAttrs = linkAttrs
    siteAttrs[.link] = URL(string: "https://binkyfiles.com")!
    credits.append(NSAttributedString(string: "binkyfiles.com\n", attributes: siteAttrs))

    var ghAttrs = linkAttrs
    ghAttrs[.link] = URL(string: "https://github.com/heyderekj/binky")!
    credits.append(NSAttributedString(string: "github.com/heyderekj/binky\n", attributes: ghAttrs))

    var supportAttrs = linkAttrs
    supportAttrs[.link] = URL(string: "mailto:\(S.supportEmail)")!
    credits.append(NSAttributedString(string: S.supportEmail, attributes: supportAttrs))

    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        NSApplication.AboutPanelOptionKey.credits: credits
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
}

/// Real installed bundle size, formatted like Finder’s **Size** for the `.app` (logical byte
/// total of regular files — not per-file allocation rounding). Uses `ByteCountFormatter` so
/// the About line matches what you see in Applications / Get Info.
private func bundleSizeString() -> String {
    let url = Bundle.main.bundleURL
    let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
    var total: Int64 = 0
    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            if let logical = values?.fileSize, logical > 0 {
                total += Int64(logical)
            } else {
                let alloc = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
                total += Int64(alloc)
            }
        }
    }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: total)
}

// MARK: - Post-crash / MetricKit prompt

/// Shown when the crash sentinel fired and/or MetricKit delivered crash diagnostics.
struct PostCrashReportSheet: View {
    let report: CrashReport
    @ObservedObject var diagnostics: DiagnosticsReporter

    private var headline: String {
        // Apple’s MetricKit English phrase; keep literal for reliable matching.
        if report.subtitle.contains("Crash diagnostics from Apple") {
            return String(localized: "Crash diagnostics", comment: "Post-crash sheet title when Apple diagnostics present.")
        }
        return String(localized: "Binky crashed last time", comment: "Post-crash sheet title for generic crash.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.headline)
                    Text(report.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)

            if let mk = report.metricKitSummary, !mk.isEmpty {
                Text(String(localized: "Apple diagnostic summary", comment: "Label above MetricKit crash summary text."))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                ScrollView {
                    Text(mk)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(.bottom, 16)
            }

            HStack {
                Button(String(localized: "Email Report…", comment: "Post-crash sheet: send report by email.")) {
                    NSWorkspace.shared.open(diagnostics.postCrashEmailURL(for: report))
                    diagnostics.dismissPendingReport()
                }
                Button(String(localized: "GitHub Issue…", comment: "Post-crash sheet: open GitHub issue.")) {
                    NSWorkspace.shared.open(diagnostics.postCrashGitHubURL(for: report))
                    diagnostics.dismissPendingReport()
                }
                Spacer()
                Button(String(localized: "Dismiss", comment: "Post-crash sheet: close without sending.")) {
                    diagnostics.dismissPendingReport()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(.ultraThinMaterial)
    }
}

// Reaches into the hosting NSWindow and clears its background so the
// SwiftUI .ultraThinMaterial above can show the blur/vibrancy through.
private struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer until the view is in the window hierarchy
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.setFrameAutosaveName("BinkyMainWindow")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("BinkyMainWindow")
    }
}
