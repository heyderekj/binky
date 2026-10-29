// Strings.swift — all user-facing copy in one place

import Foundation

/// One row for Settings → Shortcuts and any in-app reference lists.
struct KeyboardShortcutReference: Identifiable {
    let title: String
    let keys: String
    var id: String { title }
}

extension Notification.Name {
    static let binkyOpenPanel     = Notification.Name("binkyOpenPanel")
    static let binkyOpenFiles     = Notification.Name("binkyOpenFiles")
    static let binkyCheckUpdates  = Notification.Name("binkyCheckUpdates")
    static let binkyShowHistory     = Notification.Name("binkyShowHistory")
    /// Open the in-app Review triage sheet (menu bar panel). Check ``PendingReviewTriage`` on appear too.
    static let binkyShowReviewTriage = Notification.Name("binkyShowReviewTriage")
    /// Re-present the last completed batch summary (menu / shortcut).
    static let binkyShowLastBatchSummary = Notification.Name("binkyShowLastBatchSummary")
    /// `object` is `PreferencesTab.rawValue` (Int)
    static let binkySelectPreferencesTab = Notification.Name("binkySelectPreferencesTab")
    static let binkyToggleSidebar       = Notification.Name("binkyToggleSidebar")
    /// User asked to run the Downloads / default folder sweep (`Sort Downloads Now` menu, shortcuts, menu bar).
    static let binkyStartSort = Notification.Name("binkyStartSort")
    /// Sweep one routine by id (`userInfo`: ``BinkyNotificationUserInfoKey/sortRoutinePresetID`` → `UUID`).
    static let binkyStartSortForRoutine = Notification.Name("binkyStartSortForRoutine")
    /// macOS: raise the preferences ``Window`` (`openWindow(id:)` in ``BinkyShortcutCommands``).
    static let binkyOpenMacPreferences = Notification.Name("binkyOpenMacPreferences")
    /// Bring the main organizer window forward (or create one) from any AppKit context.
    static let binkyShowMainWindow = Notification.Name("binkyShowMainWindow")
    /// Another sort couldn’t start because one is already in flight.
    static let binkySortRejectedBecauseBusy = Notification.Name("binkySortRejectedBecauseBusy")
    /// Posted before quit so SwiftUI can dismiss sheets; used with `applicationShouldTerminate` / `terminateLater`.
    static let binkyPrepareQuit = Notification.Name("binkyPrepareQuit")
    /// `userInfo[BinkyNotificationUserInfoKey.mainWindowModeRaw]` is a `MainWindowMode` rawValue string (`quickSort` / `routines`).
    static let binkySwitchMainWindowMode = Notification.Name("binkySwitchMainWindowMode")
    /// Menu bar toggled **Pause watching** — syncs `UserDefaults` → SwiftUI preferences.
    static let binkyFolderWatchPauseChanged = Notification.Name("binkyFolderWatchPauseChanged")
    /// Posted when sorting progress changes. `SortProgressTracker` includes values in `userInfo`.
    static let binkySortProgressChanged = Notification.Name("binkySortProgressChanged")
    /// Thermal / LPM no longer blocks starting or continuing a held ingest batch.
    static let binkyEnergyHoldReleased = Notification.Name("binkyEnergyHoldReleased")

    /// Posted when global routing rules or preset rules change (for optional auto-sort).
    static let binkyRoutingRulesDidChange = Notification.Name("binkyRoutingRulesDidChange")
}

/// Keys for `Notification.userInfo` payloads used across the app.
enum BinkyNotificationUserInfoKey {
    /// Value: `UUID` of the ``CompressionPreset`` / routine to sweep.
    static let sortRoutinePresetID = "presetID"
    /// Value: ``MainWindowMode`` `.rawValue` string.
    static let mainWindowModeRaw = "mainWindowModeRaw"
}

enum S {
    // Drop zone — idle taglines cycle with each animation loop (English brand voice)
    static let dropIdleTaglines: [String] = [
        "Binky Free keeps your folders tidy.",
        "Sorted. Tagged. Findable.",
        "Your folders, quietly handled.",
        "Trust the trail.",
        "Folder calm.",
        "Less clutter, same files.",
    ]
    static func dropIdle(loop: Int) -> String {
        dropIdleTaglines[loop % dropIdleTaglines.count]
    }

    /// Organizer main window — empty activity area; cycles with each idle animation loop (or a timer when reduced motion is on).
    static func organizerEmptyTagline(loop: Int) -> String {
        let lines: [String] = [
            String(localized: "Fussy folder. Meet Binky.", comment: "Organizer empty state: rotating playful tagline."),
            String(localized: "Files acting up? Pop in a Binky.", comment: "Organizer empty state: rotating playful tagline."),
            String(localized: "Quiets the mess right down.", comment: "Organizer empty state: rotating playful tagline."),
            String(localized: "Files were screaming. Binky helped.", comment: "Organizer empty state: rotating playful tagline."),
            String(localized: "The pacifier for your folders.", comment: "Organizer empty state: rotating playful tagline."),
            String(localized: "Sh. Binky's handling it.", comment: "Organizer empty state: rotating playful tagline."),
        ]
        return lines[loop % lines.count]
    }

    /// Organizer watched-folder hint (shown under drop zone).
    static let organizerDropHint = String(localized: "Only files inside your watch folder can be sorted from here.", comment: "Organizer drop zone footnote.")

    static let dropHover     = "Let go."

    // Processing (English brand voice)
    static let processSingle = "On it."
    static let processBatch  = "Working through the pile."
    static let processBig    = "Big batch. Give me a moment."

    // Completion (English brand voice)
    static let doneGood      = "Done. Look how little they are now."
    static let doneMixed     = "Done. Some were already pretty lean."

    // Per-file (English brand voice)
    static let skipped       = "Already tiny. Skipped."
    static let errored       = "Couldn't crunch this one. Skipped."
    static let zeroBytes     = "Couldn't make this one any smaller. Keeping the original."

    // Buttons
    static func compressButton(_ n: Int) -> String {
        if n == 1 {
            return String(localized: "Compress 1 file", comment: "Main window: primary action when one file is queued.")
        }
        return String(localized: "Compress \(n) files", comment: "Main window: primary action when multiple files are queued. Argument is the count.")
    }
    static var clear: String { String(localized: "Clear", comment: "Toolbar or list: clear completed rows.") }

    // Preferences
    static var prefsTitle: String { String(localized: "Preferences", comment: "macOS Settings window title.") }

    /// Settings › General › Compression — parallel job cap (three tiers: 1, 3, or 8).
    static var concurrentCompressionPickerLabel: String {
        String(localized: "Batch speed", comment: "Settings: label for parallel compression limit picker.")
    }
    static var concurrentCompressionFootnote: String {
        String(localized: "How many files crunch at once — not image, video, or PDF quality. Fast is gentle; Fastest clears the queue sooner if your Mac is up for it.", comment: "Settings: explains batch parallelism tiers.")
    }

    /// Settings › General › Compression — optional largest-first batch order.
    static var batchLargestFirstLabel: String {
        String(localized: "Start with largest files", comment: "Settings: toggle to schedule big files first in a batch.")
    }
    static var batchLargestFirstFootnote: String {
        String(localized: "When enabled, the longest jobs run first so the batch tends to finish sooner. The default is smallest first for faster early feedback.", comment: "Settings: explains batch ordering toggle.")
    }

    static func concurrentCompressionTierOption(limit: Int) -> String {
        switch limit {
        case 1: return "Fast — one at a time, steady pace"
        case 3: return "Faster — up to three in parallel"
        case 8: return "Fastest — up to eight, all cores welcome"
        default: return "Up to \(limit)"
        }
    }

    /// Plain label for assistive tech (localized).
    static func concurrentCompressionAccessibilityLabel(limit: Int) -> String {
        switch limit {
        case 1:
            return String(localized: "Up to one file compressing at a time", comment: "VoiceOver label for batch speed option.")
        case 3:
            return String(localized: "Up to three files compressing at a time", comment: "VoiceOver label for batch speed option.")
        case 8:
            return String(localized: "Up to eight files compressing at a time", comment: "VoiceOver label for batch speed option.")
        default:
            return String(localized: "Up to \(limit) files compressing at a time", comment: "VoiceOver label for batch speed option; argument is numeric limit.")
        }
    }

    // Format names (technical; keep recognizable)
    static let webp = "WebP"
    static let avif = "AVIF"
    static let png  = "PNG"
    static let heic = "HEIC"

    /// Shown in About, Settings, and linked with `mailto:`.
    static let supportEmail = "derek@testamentmade.com"

    // Paste from clipboard
    static var pasteEmptyTitle: String { String(localized: "Nothing to paste", comment: "Alert title when clipboard has no compressible item.") }
    static var pasteEmptyMessage: String {
        String(localized: "Copy a supported file in Finder, or copy an image (PNG or TIFF), then try again.", comment: "Alert message for empty clipboard paste.")
    }
    static var pasteDuplicateTitle: String { String(localized: "Already in the list", comment: "Alert title when pasted file is already queued.") }
    static var pasteDuplicateMessage: String {
        String(localized: "That file is already queued — drop something new or clear the list first.", comment: "Alert message for duplicate paste.")
    }

    // Settings → Shortcuts
    static var shortcutsTabServicesFooter: String {
        String(localized: "Assign shortcuts for Finder’s “Sort with Binky” in System Settings → Keyboard → Keyboard Shortcuts → Services.", comment: "Settings Shortcuts tab footer.")
    }
    static func shortcutsTabHelpFooter(helpMenuShortcut: String) -> String {
        String(localized: "For watch folders, routines, and full troubleshooting, open Binky Help from the Help menu (\(helpMenuShortcut)).", comment: "Settings Shortcuts tab footer; argument is help shortcut.")
    }
    static var shortcutsAppDescription: String {
        String(localized: "Binky exposes a Sort Files action in the Shortcuts app. Hand files from Finder or other actions through Binky — same routing rules as the main window.", comment: "Settings: Shortcuts app integration description.")
    }

    static var shortcutsCustomizableHeader: String { String(localized: "Customize", comment: "Settings Shortcuts section header.") }
    static var shortcutsFixedHeader: String { String(localized: "System & help", comment: "Settings Shortcuts section header for fixed shortcuts.") }
    static var shortcutsResetAll: String { String(localized: "Reset All Shortcuts", comment: "Button to reset all custom shortcuts.") }
    static var shortcutsResetRow: String { String(localized: "Reset", comment: "Button to reset one shortcut row.") }
    static var shortcutsEdit: String { String(localized: "Edit", comment: "Button to start recording a new shortcut.") }
    static var shortcutsCancelEdit: String { String(localized: "Cancel", comment: "Button to cancel shortcut recording.") }
    static var shortcutsRecorderPrompt: String { String(localized: "Press a key…", comment: "Placeholder while waiting for shortcut keys.") }
    static var shortcutsRecorderHint: String {
        String(localized: "Press a combo to save · Esc to cancel · Delete to reset", comment: "Hint under shortcut recorder field.")
    }
    static var shortcutsConflictPrefix: String { String(localized: "Already used by", comment: "Prefix when shortcut conflicts; followed by action name.") }
    static var shortcutsSystemWarningPrefix: String { String(localized: "Overrides macOS:", comment: "Prefix when shortcut may override a system shortcut.") }

    /// Non-customizable menu items (matches `BinkyFixedShortcut` + system Settings).
    static var fixedMenuShortcutReference: [KeyboardShortcutReference] {
        BinkyFixedShortcut.allCases.map {
            KeyboardShortcutReference(title: $0.title, keys: $0.shortcut.displayString)
        }
    }
}
