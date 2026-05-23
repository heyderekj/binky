import Darwin
import Foundation

/// Reads `kMDItemWhereFroms` from browser / app download metadata (`com.apple.metadata:kMDItemWhereFroms`).
public enum WhereFromsReader {
    public static let xattrName = "com.apple.metadata:kMDItemWhereFroms"

    /// Ordered list of source URLs (page, then often the asset URL).
    public static func sourceURLs(forFileAt url: URL) -> [URL] {
        let path = url.path
        guard let data = readXattr(path: path, name: xattrName), !data.isEmpty else { return [] }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [] }
        return urls(fromPlistObject: plist)
    }

    /// Host labels from each where-from URL (lowercased, no port).
    public static func originHosts(forFileAt url: URL) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for u in sourceURLs(forFileAt: url) {
            guard let host = normalizedHost(from: u), !host.isEmpty else { continue }
            if seen.insert(host).inserted {
                out.append(host)
            }
        }
        return out
    }

    /// First page-like host when available (prefers HTTPS `http` URLs that look like pages over raw asset hosts).
    public static func primaryOriginHost(forFileAt url: URL) -> String? {
        originHosts(forFileAt: url).first
    }

    /// Wildcard domain patterns: `*.stripe.com`, `figma.com`. Empty pattern list = no constraint (handled by caller).
    public static func matchesAnyOriginPattern(_ patterns: [String], hosts: [String]) -> Bool {
        let trimmed = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return true }
        for host in hosts {
            for pattern in trimmed where domainMatches(pattern: pattern, host: host) {
                return true
            }
        }
        return false
    }

    // MARK: - Glob matching

    /// `*.example.com` matches `sub.example.com` and `example.com`. `example.com` matches `example.com` and `www.example.com`.
    public static func domainMatches(pattern: String, host: String) -> Bool {
        let h = host.lowercased()
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !p.isEmpty else { return true }
        if p == "*" { return true }
        if p.hasPrefix("*.") {
            let suffix = String(p.dropFirst(2))
            guard !suffix.isEmpty else { return false }
            return h == suffix || h.hasSuffix("." + suffix)
        }
        if h == p { return true }
        if h == "www.\(p)" { return true }
        return false
    }

    public static func sanitizedOriginLabel(forHost host: String?) -> String {
        guard let host, !host.isEmpty else { return "" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        return String(host.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("-") })
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Private

    private static func readXattr(path: String, name: String) -> Data? {
        // XATTR_NOFOLLOW: read the xattr on the symlink itself, not its target. Without this,
        // a symlink in Downloads pointing to an unrelated file would leak that file's download
        // origin metadata into rule matching.
        let sz = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard sz > 0 else { return nil }
        var data = Data(count: sz)
        let got: ssize_t = data.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return ssize_t(-1) }
            return getxattr(path, name, base, sz, 0, XATTR_NOFOLLOW)
        }
        guard got == sz else { return nil }
        return data
    }

    private static func urls(fromPlistObject object: Any) -> [URL] {
        if let strings = object as? [String] {
            return strings.compactMap { URL(string: $0) }
        }
        if let datas = object as? [Data] {
            var out: [URL] = []
            for d in datas {
                if let s = String(data: d, encoding: .utf8), let u = URL(string: s) {
                    out.append(u)
                }
            }
            return out
        }
        if let arr = object as? [Any] {
            var out: [URL] = []
            for item in arr {
                if let s = item as? String, let u = URL(string: s) {
                    out.append(u)
                } else if let d = item as? Data, let s = String(data: d, encoding: .utf8), let u = URL(string: s) {
                    out.append(u)
                }
            }
            return out
        }
        return []
    }

    private static func normalizedHost(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }
}
