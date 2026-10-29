import AppKit
import SwiftUI

/// Minimal menu bar controls: sort, pause/resume watch, show main window, Settings.
@MainActor
final class BinkyMenuBarController: NSObject, NSMenuDelegate {
    static let shared = BinkyMenuBarController()

    private var statusItem: NSStatusItem?
    private var menuBarPercentTimer: Timer?
    private var menuBarShownPercent: CGFloat = 0

    private var panel: MenuBarPanelWindow?
    private let panelModel = MenuBarPanelModel()
    private var panelClickMonitors: [Any] = []

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
            // The app icon's pacifier, like Dinky's and Slinky's own marks in the menu bar.
            item.button?.image = BinkyMenuBarIcon.image
            if #available(macOS 27.0, *) {
                // Glass panel instead of a menu; the system drives open/close and keyboard navigation.
                item.expandedInterfaceDelegate = self
            } else {
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
            }
            statusItem = item
        }
        if let menu = statusItem?.menu {
            menuNeedsUpdate(menu)
        }
        refreshMenuBarProgressChrome()
    }

    private func tearDown() {
        closePanel()
        invalidateMenuBarPercentTimer()
        menuBarShownPercent = 0
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func sortProgressDidChange() {
        refreshMenuBarProgressChrome()
        if panel != nil { reloadPanelModel() }
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
        sortRoutine(id: uuid)
    }

    private func sortRoutine(id uuid: UUID) {
        NotificationCenter.default.post(
            name: .binkyStartSortForRoutine,
            object: nil,
            userInfo: [BinkyNotificationUserInfoKey.sortRoutinePresetID: uuid]
        )
    }

    nonisolated static func enabledRoutinesFromDefaults() -> [CompressionPreset] {
        guard let data = UserDefaults.standard.data(forKey: "savedPresetsData"),
              let presets = try? JSONDecoder().decode([CompressionPreset].self, from: data) else {
            return []
        }
        return presets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    nonisolated static func menuBarRoutineDisplayTitle(_ preset: CompressionPreset) -> String {
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
        if panel != nil { reloadPanelModel() }
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

// MARK: - macOS 27 glass panel

/// Borderless panel that can take key focus (arrow keys, Esc) without activating Binky.
final class MenuBarPanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

extension BinkyMenuBarController {
    private func reloadPanelModel() {
        panelModel.watchingPaused = UserDefaults.standard.bool(forKey: "folderWatch.paused")
        panelModel.reviewCount = BinkyPreferences.current?.reviewFolderItemCount() ?? 0
        panelModel.lastSort = BinkyPrefsStore().loadSessionHistory().first
        panelModel.routines = Self.enabledRoutinesFromDefaults()
            .map { MenuBarPanelModel.Routine(id: $0.id, title: Self.menuBarRoutineDisplayTitle($0)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var panelActions: MenuBarPanelActions {
        MenuBarPanelActions(
            sortAll: { [weak self] in self?.sortNow() },
            sortRoutine: { [weak self] id in self?.sortRoutine(id: id) },
            togglePauseSorting: { [weak self] in self?.togglePauseSorting() },
            stopSorting: { [weak self] in self?.stopSortingNow() },
            togglePauseWatching: { [weak self] in self?.togglePauseWatching() },
            tidyReview: { [weak self] in
                self?.dismissPanel()
                PendingWindowRequest.post(.reviewTriage)
                self?.showMainWindow()
            },
            showHistory: { [weak self] in self?.dismissPanel(); self?.openHistory() },
            showMainWindow: { [weak self] in self?.dismissPanel(); self?.showMainWindow() },
            openSettings: { [weak self] in self?.dismissPanel(); self?.openSettings() },
            quit: { [weak self] in self?.dismissPanel(); self?.terminateApp() }
        )
    }

    fileprivate func showPanel(below item: NSStatusItem) {
        guard let button = item.button, let buttonWindow = button.window else { return }
        reloadPanelModel()

        let host = NSHostingView(rootView: MenuBarPanelView(model: panelModel, actions: panelActions))
        let size = host.fittingSize
        // Same backing as Slinky's panel: the menu material, 12pt corners.
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        let panel = panel ?? {
            let p = MenuBarPanelWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            p.isFloatingPanel = true
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            p.onCancel = { [weak self] in self?.dismissPanel() }
            return p
        }()
        panel.contentView = effect

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = buttonRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = buttonRect.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Clicks anywhere else end the session, like a menu.
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissPanel() }
        }
        let inside = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self.panel, event.window !== buttonWindow {
                self.dismissPanel()
            }
            return event
        }
        panelClickMonitors = [outside, inside].compactMap { $0 }
    }

    /// Ends the expanded-interface session; AppKit then calls back to close the panel.
    private func dismissPanel() {
        if #available(macOS 27.0, *), let session = statusItem?.expandedInterfaceSession {
            session.cancel()
        } else {
            closePanel()
        }
    }

    fileprivate func closePanel() {
        panelClickMonitors.forEach(NSEvent.removeMonitor)
        panelClickMonitors = []
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
}

@available(macOS 27.0, *)
extension BinkyMenuBarController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        showPanel(below: statusItem)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        closePanel()
    }
}

/// Binky's pacifier as a template glyph: teat, shield and ring, as in the app icon.
/// About 12.5 × 11pt of ink, in line with Slinky's mark and the system's own items.
enum BinkyMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
                CGRect(x: rect.minX + x - r, y: rect.minY + y - r, width: 2 * r, height: 2 * r)
            }
            let gap: CGFloat = 1.1
            let teatFrom = CGPoint(x: rect.minX + 4.4, y: rect.minY + 12.6)
            let teatTo = CGPoint(x: rect.minX + 7.2, y: rect.minY + 10.4)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)

            // Shield.
            ctx.fillEllipse(in: circle(10.2, 11.0, 3.1))
            ctx.fillEllipse(in: circle(8.2, 7.4, 3.3))
            // Ring, cut free of the shield.
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: circle(12.6, 6.3, 3.0 + gap))
            ctx.setBlendMode(.normal)
            ctx.fillEllipse(in: circle(12.6, 6.3, 3.0))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: circle(12.6, 6.3, 1.55))
            // Teat, on top.
            ctx.setLineWidth(4.4 + 2 * gap)
            ctx.move(to: teatFrom)
            ctx.addLine(to: teatTo)
            ctx.strokePath()
            ctx.setBlendMode(.normal)
            ctx.setLineWidth(4.4)
            ctx.move(to: teatFrom)
            ctx.addLine(to: teatTo)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Binky"
        return image
    }()
}
