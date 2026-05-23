import BinkyCoreShared
import Foundation

// MARK: - Output

/// Output of `OriginHostStage`. Captures every download-source host attached
/// to a file's `kMDItemWhereFroms` xattr, in the order Browsers / AirDrop /
/// other writers recorded them.
///
/// The first entry is conventionally the "page" host (e.g. `stripe.com`); the
/// later entries are typically the asset host (`d1.cdn.stripe.com`,
/// `cloudfront.net`). Routing rules that match by domain (`*.stripe.com`)
/// should usually look at the whole `hosts` list, not just `primary`, because
/// CDNs commonly host the asset under a different domain than the page.
public struct OriginHosts: Equatable, Sendable {
    public let url: URL
    public let hosts: [String]

    public init(url: URL, hosts: [String]) {
        self.url = url
        self.hosts = hosts
    }

    /// Convenience: the first host, if any. Equivalent to
    /// `WhereFromsReader.primaryOriginHost(forFileAt:)`.
    public var primary: String? { hosts.first }
}

// MARK: - Stage

/// Reads `kMDItemWhereFroms` for the input URL and returns an `OriginHosts`
/// record. Wraps the existing v1 `WhereFromsReader.originHosts(forFileAt:)`
/// helper without re-implementing the xattr / plist parsing.
///
/// **Why a separate stage**
///
/// In v1, `SortWork.processOne` calls `WhereFromsReader.primaryOriginHost(forFileAt:)`
/// inline, mid-loop. That makes it hard to test routing rules that depend on
/// origin host without spinning up a full sort run. As an isolated stage:
/// - Tests can fixture an xattr on a temp file and assert the stage's output.
/// - The future `RuleMatchStage` consumes `OriginHosts` directly instead of
///   re-reading the xattr.
/// - A future "lookup origin via Spotlight metadata index instead of xattr"
///   experiment can swap this stage out cleanly.
///
/// The stage is `Sendable` and stateless, so it composes safely into
/// concurrent pipelines.
public struct OriginHostStage: PipelineStage {
    public typealias Input = URL
    public typealias Output = OriginHosts

    public init() {}

    public func run(_ input: URL, context: PipelineContext) async throws -> OriginHosts {
        let hosts = WhereFromsReader.originHosts(forFileAt: input)
        return OriginHosts(url: input, hosts: hosts)
    }
}
