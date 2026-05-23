import BinkyCoreShared
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Result

public struct ExecutionResult: Sendable, Equatable {
    public let suggestion: Suggestion
    public let outcome: Outcome

    public enum Outcome: Sendable, Equatable {
        /// File was successfully moved/renamed/trashed.
        case success(destinationPath: String?)
        /// Action was .keep — no filesystem change.
        case kept
        /// Something went wrong; `reason` is human-readable.
        case failure(reason: String)
    }

    public init(suggestion: Suggestion, outcome: Outcome) {
        self.suggestion = suggestion
        self.outcome = outcome
    }

    public var succeeded: Bool {
        switch outcome {
        case .success, .kept: return true
        case .failure: return false
        }
    }
}

// MARK: - Executor

/// Applies a `Suggestion`'s `ProposedAction` to the filesystem.
///
/// **Design**
///
/// Stateless, `Sendable`, no side effects beyond the filesystem operation
/// itself. The caller (Daily Calm UI) is responsible for:
/// - Recording the decision in `SuggestionStore` (already done before calling).
/// - Updating the UI state (card turns green / shows error).
/// - Optionally recording the move in v1 history for undo (future work).
///
/// **Collision handling**
///
/// Move uses `SortCollision.uniquify` — the same Finder-style " 2", " 3"
/// suffix logic v1 uses. If the destination directory doesn't exist, we
/// create it (matching v1's `StarterDestinations.ensure` behavior).
///
/// **Trash**
///
/// On macOS we use `FileManager.trashItem(at:resultingItemURL:)` which
/// moves to the user's Trash and supports Put Back. On platforms without
/// Trash (hypothetical future CLI-only path) we fall back to
/// `removeItem(at:)`.
public struct SuggestionExecutor: Sendable {

    public init() {}

    public func execute(_ suggestion: Suggestion) -> ExecutionResult {
        let source = suggestion.source

        // Pre-check: source must still exist. Between the time the engine
        // proposed and the user clicked Apply, the file may have been moved
        // by another process, Finder, or a v1 sort run.
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            return ExecutionResult(
                suggestion: suggestion,
                outcome: .failure(reason: "File no longer exists at \(source.lastPathComponent).")
            )
        }

        switch suggestion.action {
        case .move(let destination):
            return executeMove(source: source, destinationDir: destination, fm: fm)

        case .rename(let newName):
            return executeRename(source: source, newName: newName, fm: fm)

        case .trash:
            return executeTrash(source: source, fm: fm)

        case .keep:
            return ExecutionResult(suggestion: suggestion, outcome: .kept)

        case .runShortcut(let name):
            return executeShortcut(name: name, suggestion: suggestion)
        }
    }

    // MARK: - Move

    private func executeMove(source: URL, destinationDir: URL, fm: FileManager) -> ExecutionResult {
        do {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            let target = SortCollision.uniquify(
                destinationDirectory: destinationDir,
                preferredFilename: source.lastPathComponent
            )
            try fm.moveItem(at: source, to: target)
            return ExecutionResult(
                suggestion: Suggestion(id: UUID(), source: source, action: .move(to: destinationDir), reasoning: ""),
                outcome: .success(destinationPath: target.path)
            )
        } catch {
            return ExecutionResult(
                suggestion: Suggestion(id: UUID(), source: source, action: .move(to: destinationDir), reasoning: ""),
                outcome: .failure(reason: error.localizedDescription)
            )
        }
    }

    // MARK: - Rename

    private func executeRename(source: URL, newName: String, fm: FileManager) -> ExecutionResult {
        let dir = source.deletingLastPathComponent()
        let target = SortCollision.uniquify(destinationDirectory: dir, preferredFilename: newName)
        do {
            try fm.moveItem(at: source, to: target)
            return ExecutionResult(
                suggestion: Suggestion(id: UUID(), source: source, action: .rename(to: newName), reasoning: ""),
                outcome: .success(destinationPath: target.path)
            )
        } catch {
            return ExecutionResult(
                suggestion: Suggestion(id: UUID(), source: source, action: .rename(to: newName), reasoning: ""),
                outcome: .failure(reason: error.localizedDescription)
            )
        }
    }

    // MARK: - Trash

    private func executeTrash(source: URL, fm: FileManager) -> ExecutionResult {
        do {
            var trashURL: NSURL?
            try fm.trashItem(at: source, resultingItemURL: &trashURL)
            return ExecutionResult(
                suggestion: Suggestion(id: UUID(), source: source, action: .trash, reasoning: ""),
                outcome: .success(destinationPath: trashURL?.path)
            )
        } catch {
            return ExecutionResult(
                suggestion: Suggestion(id: UUID(), source: source, action: .trash, reasoning: ""),
                outcome: .failure(reason: error.localizedDescription)
            )
        }
    }

    // MARK: - Shortcut

    private func executeShortcut(name: String, suggestion: Suggestion) -> ExecutionResult {
        #if canImport(AppKit)
        // shortcuts://run-shortcut?name=<encoded>&input=<path>
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "input", value: suggestion.source.path),
        ]
        guard let url = components.url else {
            return ExecutionResult(suggestion: suggestion, outcome: .failure(reason: "Could not build Shortcuts URL."))
        }
        let ok = NSWorkspace.shared.open(url)
        return ExecutionResult(
            suggestion: suggestion,
            outcome: ok ? .success(destinationPath: nil) : .failure(reason: "Shortcuts app didn't respond.")
        )
        #else
        return ExecutionResult(suggestion: suggestion, outcome: .failure(reason: "Shortcuts not available on this platform."))
        #endif
    }
}
