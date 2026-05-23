import AppKit

/// Minimal menu bar controls: sort, pause/resume watch, show main window, Settings.
@MainActor
final class BinkyMenuBarController: NSObject, NSMenuDelegate {
    static let shared = BinkyMenuBarController()

    private var statusItem: NSStatusItem?
    private var menuBarPercentTimer: Timer?
    private var menuBarShownPercent: CGFloat = 0

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sortProgressDidChange),
            name: .binkySortProgressChanged,
            object: nil
        )
        // Prime idle tooltip/title expectations when the observer fires later.
        menuBarShownPercent = 0
    }

    func refresh() {
        let defaults = UserDefaults.standard
        let enabled: Bool = {
            if defaults.object(forKey: "ui.showMenuBarIcon") == nil { return true }
            return defaults.bool(forKey: "ui.showMenuBarIcon")
        }()

        guard enabled else {
            tearDown()
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.toolTip = String(localized: "Binky", comment: "Menu bar status item tooltip (idle).")
            item.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Binky")
            item.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        if let menu = statusItem?.menu {
            menuNeedsUpdate(menu)
        }
        refreshMenuBarProgressChrome()
    }

    private func tearDown() {
        invalidateMenuBarPercentTimer()
        menuBarShownPercent = 0
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func sortProgressDidChange() {
        refreshMenuBarProgressChrome()
    }

    /// Eased `%` beside the tray icon while sorting — reads live state from ``SortProgressTracker``.
    private func refreshMenuBarProgressChrome() {
        guard let btn = statusItem?.button else {
            invalidateMenuBarPercentTimer()
            menuBarShownPercent = 0
            return
        }

        let tracker = SortProgressTracker.shared
        guard tracker.isActive else {
            invalidateMenuBarPercentTimer()
            menuBarShownPercent = 0
            btn.title = ""
            btn.toolTip = String(localized: "Binky", comment: "Menu bar status item tooltip (idle).")
            return
        }

        btn.toolTip = tracker.menuBarTooltip()
        scheduleMenuBarPercentTimerIfNeeded()
        syncMenuBarButtonTitleEase(btn)
    }

    private func scheduleMenuBarPercentTimerIfNeeded() {
        guard menuBarPercentTimer == nil else { return }
        menuBarPercentTimer = Timer.scheduledTimer(withTimeInterval: 0.058, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncMenuBarButtonTitleEase(self.statusItem?.button)
            }
        }
        menuBarPercentTimer?.tolerance = 0.012
    }

    private func invalidateMenuBarPercentTimer() {
        menuBarPercentTimer?.invalidate()
        menuBarPercentTimer = nil
    }

    /// Interpolates the displayed integer `%` toward the batch fraction instead of snapping per file.
    private func syncMenuBarButtonTitleEase(_ btn: NSButton?) {
        guard let btn else { return }
        let tracker = SortProgressTracker.shared
        guard tracker.isActive else { return }

        let targetPct = CGFloat(tracker.fraction * 100)
        let delta = targetPct - menuBarShownPercent
        if abs(delta) < CGFloat(0.35) {
            menuBarShownPercent = targetPct
        } else {
            menuBarShownPercent += delta * CGFloat(0.42)
        }
        let rounded = Int((menuBarShownPercent + CGFloat(1e-4)).rounded())
        let clipped = Swift.max(0, Swift.min(100, rounded))
        btn.title = " \(clipped)%"
        btn.toolTip = tracker.menuBarTooltip()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabledPresets = Self.enabledRoutinesFromDefaults()
        let isSorting = DownloadsSortOrchestrator.shared.isSorting

        if enabledPresets.count > 1 {
            let sortParent = NSMenuItem(
                title: String(localized: "Sort", comment: "Menu bar: parent menu for choosing which folder to sweep."),
                action: nil,
                keyEquivalent: ""
            )
            let submenu = NSMenu()
            let sortAll = NSMenuItem(
                title: String(localized: "Sort All Folders", comment: "Menu bar: sweep every enabled routine."),
                action: #selector(sortNow),
                keyEquivalent: ""
            )
            sortAll.target = self
            sortAll.isEnabled = !isSorting
            submenu.addItem(sortAll)
            submenu.addItem(.separator())
            let sorted = enabledPresets.sorted {
                Self.menuBarRoutineDisplayTitle($0).localizedCaseInsensitiveCompare(Self.menuBarRoutineDisplayTitle($1)) == .orderedAscending
            }
            for preset in sorted {
                let row = NSMenuItem(
                    title: Self.menuBarRoutineDisplayTitle(preset),
                    action: #selector(sortRoutineNow(_:)),
                    keyEquivalent: ""
                )
                row.target = self
                row.representedObject = preset.id.uuidString
                row.isEnabled = !isSorting
                submenu.addItem(row)
            }
            sortParent.submenu = submenu
            sortParent.isEnabled = !isSorting
            menu.addItem(sortParent)
        } else {
            let sort = NSMenuItem(
                title: String(localized: "Sort Now", comment: "Menu bar command."),
                action: #selector(sortNow),
                keyEquivalent: ""
            )
            sort.target = self
            sort.isEnabled = !isSorting
            menu.addItem(sort)
        }

        let tracker = SortProgressTracker.shared
        if tracker.isActive {
            let isPaused = tracker.runState == .paused
            let sortPauseResume = NSMenuItem(
                title: isPaused
                    ? String(localized: "Resume sorting", comment: "Menu bar command.")
                    : String(localized: "Pause sorting", comment: "Menu bar command."),
                action: #selector(togglePauseSorting),
                keyEquivalent: ""
            )
            sortPauseResume.target = self
            sortPauseResume.isEnabled = tracker.runState != .stopping
            menu.addItem(sortPauseResume)

            let stopSorting = NSMenuItem(
                title: String(localized: "Stop sorting", comment: "Menu bar command."),
                action: #selector(stopSortingNow),
                keyEquivalent: ""
            )
            stopSorting.target = self
            stopSorting.isEnabled = tracker.runState != .stopping
            menu.addItem(stopSorting)
        }

        let paused = UserDefaults.standard.bool(forKey: "folderWatch.paused")
        let pauseItem = NSMenuItem(
            title: paused
                ? String(localized: "Resume watching", comment: "Menu bar command.")
                : String(localized: "Pause watching", comment: "Menu bar command."),
            action: #selector(togglePauseWatching),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let show = NSMenuItem(
            title: String(localized: "Show Binky", comment: "Menu bar command."),
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        show.target = self
        menu.addItem(show)

        let settings = NSMenuItem(
            title: String(localized: "Settings…", comment: "Menu bar command."),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let history = NSMenuItem(
            title: String(localized: "History…", comment: "Menu bar command."),
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit Binky", comment: "Menu bar command."),
            action: #selector(terminateApp),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openHistory() {
        NotificationCenter.default.post(name: .binkyShowHistory, object: nil)
        GlobalHotkeyManager.activateMainWindow()
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }

    @objc private func sortNow() {
        NotificationCenter.default.post(name: .binkyStartSort, object: nil)
    }

    @objc private func sortRoutineNow(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString) else { return }
        NotificationCenter.default.post(
            name: .binkyStartSortForRoutine,
            object: nil,
            userInfo: [BinkyNotificationUserInfoKey.sortRoutinePresetID: uuid]
        )
    }

    private static func enabledRoutinesFromDefaults() -> [Inbox] {
        guard let data = UserDefaults.standard.data(forKey: "savedPresetsData"),
              let presets = try? JSONDecoder().decode([Inbox].self, from: data) else {
            return []
        }
        return presets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func menuBarRoutineDisplayTitle(_ preset: Inbox) -> String {
        let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        let path = preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path as NSString).lastPathComponent
    }

    @objc private func togglePauseSorting() {
        let tracker = SortProgressTracker.shared
        if tracker.runState == .paused {
            DownloadsSortOrchestrator.shared.resumeCurrentSort()
        } else if tracker.runState == .running {
            DownloadsSortOrchestrator.shared.pauseCurrentSort()
        }
    }

    @objc private func stopSortingNow() {
        DownloadsSortOrchestrator.shared.stopCurrentSort()
    }

    @objc private func togglePauseWatching() {
        let key = "folderWatch.paused"
        let next = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(next, forKey: key)
        NotificationCenter.default.post(name: .binkyFolderWatchPauseChanged, object: nil)
    }

    @objc private func showMainWindow() {
        // SwiftUI Commands bridge in `BinkyApp` (`BinkyShortcutCommands`) listens for this
        // notification and calls `openWindow(id: "main")` — the only reliable way to
        // (re)create or refocus a `WindowGroup` window from the AppKit menu bar, including
        // when the user has closed the main window entirely. We post on the next runloop tick
        // so AppKit finishes dismissing the status menu first.
        DispatchQueue.main.async {
            NSApp.activate()
            NotificationCenter.default.post(name: .binkyShowMainWindow, object: nil)
        }
    }

    @objc private func openSettings() {
        NSApp.activate()
        // `BinkyShortcutCommands` listens for this and calls `openWindow(id:)` — works even when
        // the organizer window (and `ContentView`) isn’t mounted.
        NotificationCenter.default.post(name: .binkyOpenMacPreferences, object: nil)
    }
}
