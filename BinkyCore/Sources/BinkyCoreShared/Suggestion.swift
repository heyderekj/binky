import Foundation

// MARK: - Proposed action

/// Concrete file-system intent a `Suggestion` proposes. Kept narrow and testable —
/// the v1 pipeline supports seven action variants (zip / extract / DMG-install /
/// tag-fanout / etc.); v2 Daily Calm collapses that surface to four because the
/// edges (zip, install) sit outside the "move things to the right place" core
/// and either belong elsewhere (Finder, Dinky) or are too rare to warrant first-class UI.
public enum ProposedAction: Equatable, Codable, Sendable {
    /// Relocate the source to a different directory. The new file's basename is
    /// preserved unless paired with a `.rename` proposal in the same `Suggestion`.
    case move(to: URL)

    /// Rename in place (or in tandem with a `.move`). The new name MUST already
    /// include the extension; callers should not derive it implicitly.
    case rename(to: String)

    /// Move to the user's Trash. Reversible from Finder — preferred over outright delete.
    case trash

    /// Explicit "leave it alone, don't ask again about this exact file." Recorded
    /// so the engine learns the user's keep preferences over time.
    case keep

    /// Hand the file off to a user-defined Apple Shortcut. The shortcut name is
    /// resolved at apply-time, not when the suggestion is created — if the user
    /// renames or deletes the shortcut between proposal and apply, the action fails
    /// gracefully rather than crashing.
    case runShortcut(name: String)
}

// MARK: - Confidence

/// 0.0–1.0 score; semantically: how sure the engine is that the proposal is correct.
///
/// Conventions (not enforced by the type — kept human-readable in code review):
/// - **≥ 0.9** — High confidence (exact rule match, byte-identical duplicate, etc.).
///   Safe candidate for "auto-apply once the user has accepted N similar suggestions."
/// - **0.6–0.9** — Reasonable confidence (heuristic + AI signal agree). Default
///   surface area for Daily Calm.
/// - **< 0.6** — Low confidence (AI guess only, no corroborating signal). Should
///   never be auto-applied, and Daily Calm sorts these to the bottom.
public typealias SuggestionConfidence = Double

// MARK: - User decision

/// What the user decided about a `Suggestion`. The history of decisions is the
/// learning signal for "auto-apply pre-approved patterns" in v2.x.
public enum UserDecision: String, Codable, Sendable, CaseIterable {
    /// Awaiting review. Shown in Daily Calm.
    case pending

    /// User confirmed the proposal — the engine will execute the action and record
    /// the decision in history.
    case accepted

    /// User rejected the proposal. The file stays where it is; the engine records
    /// "this proposal type was wrong for this kind of file" for future tuning.
    case rejected

    /// User postponed the decision (skip in Daily Calm). The suggestion stays
    /// pending but drops in priority for the next session.
    case snoozed
}

// MARK: - Suggestion

/// One proposal to act on a single file. The unit of communication between the
/// suggestion engine and the Daily Calm UI.
///
/// **Why a dedicated type vs reusing `SortBatchEntry`?**
///
/// `SortBatchEntry` describes what *already happened* (post-move audit row).
/// `Suggestion` describes what *might happen, pending user decision*. Conflating
/// them is the v1 design mistake we're walking back: there's no clean place in
/// `SortBatchEntry` for `confidence`, `reasoning`, or `userDecision`, and the
/// transition "pending → accepted → executed → recorded" is much easier to reason
/// about with two distinct types and a clear handoff.
public struct Suggestion: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID

    /// File the suggestion applies to. Kept as a `URL` for callers that already
    /// have one; for storage we serialize via `path`.
    public let source: URL

    public let action: ProposedAction

    /// Optional. `nil` means "produced by deterministic rule, no probability semantic."
    public let confidence: SuggestionConfidence?

    /// Human-readable single-line explanation surfaced to the user. Should fit on one
    /// line in the Daily Calm card. Examples:
    /// - "Receipt detected (vendor: Acme, $1,200)"
    /// - "Matches your `Client invoices` rule"
    /// - "Looks like a duplicate of `~/Pictures/IMG_4839.jpg`"
    public let reasoning: String

    public let createdAt: Date

    /// `nil` until the user makes a call. Updated in place by the engine; serialized so
    /// `accepted` / `rejected` history persists across launches.
    public var userDecision: UserDecision?

    public init(
        id: UUID = UUID(),
        source: URL,
        action: ProposedAction,
        confidence: SuggestionConfidence? = nil,
        reasoning: String,
        createdAt: Date = Date(),
        userDecision: UserDecision? = nil
    ) {
        self.id = id
        self.source = source
        self.action = action
        self.confidence = confidence
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.userDecision = userDecision
    }

    // MARK: Codable — URL persisted as POSIX path for human-readable JSON.

    enum CodingKeys: String, CodingKey {
        case id, sourcePath, action, confidence, reasoning, createdAt, userDecision
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let path = try c.decode(String.self, forKey: .sourcePath)
        source = URL(fileURLWithPath: path)
        action = try c.decode(ProposedAction.self, forKey: .action)
        confidence = try c.decodeIfPresent(SuggestionConfidence.self, forKey: .confidence)
        reasoning = try c.decode(String.self, forKey: .reasoning)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        userDecision = try c.decodeIfPresent(UserDecision.self, forKey: .userDecision)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source.path, forKey: .sourcePath)
        try c.encode(action, forKey: .action)
        try c.encodeIfPresent(confidence, forKey: .confidence)
        try c.encode(reasoning, forKey: .reasoning)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(userDecision, forKey: .userDecision)
    }
}

// MARK: - Convenience predicates

public extension Suggestion {
    var isPending: Bool { userDecision == nil || userDecision == .pending }
    var isAccepted: Bool { userDecision == .accepted }
    var isRejected: Bool { userDecision == .rejected }
    var isSnoozed: Bool { userDecision == .snoozed }
}
