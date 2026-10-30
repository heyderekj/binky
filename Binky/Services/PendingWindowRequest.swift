import Foundation

/// Work for the main window that may arrive before the window exists (menu bar panel, Siri, Shortcuts).
/// Callers queue it and open the window; the window takes it on appear or on the notification,
/// whichever comes first, so each request runs once.
@MainActor
enum PendingWindowRequest: Equatable {
    case reviewTriage
    /// `nil` sorts the default folder (or every routine, same as **Sort Now**).
    case sort(routineID: UUID?)

    private static var queue: [PendingWindowRequest] = []

    static func post(_ request: PendingWindowRequest) {
        queue.append(request)
        NotificationCenter.default.post(name: .binkyPendingWindowRequest, object: nil)
    }

    /// Still waiting for a window to take it.
    static var hasPending: Bool { !queue.isEmpty }

    /// True once per queued triage request.
    static func takeReviewTriage() -> Bool {
        guard queue.contains(.reviewTriage) else { return false }
        queue.removeAll { $0 == .reviewTriage }
        return true
    }

    static func takeSorts() -> [UUID?] {
        var sorts: [UUID?] = []
        queue.removeAll { request in
            guard case let .sort(routineID) = request else { return false }
            sorts.append(routineID)
            return true
        }
        return sorts
    }
}
