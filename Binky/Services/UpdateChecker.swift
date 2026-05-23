// UpdateChecker.swift — polls GitHub Releases for a newer Binky.
// Zero dependencies. Pure URLSession + Codable.

import AppKit
import Foundation
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {

    // MARK: - Published state
    @Published var availableVersion: String? = nil   // nil = up to date or unchecked
    @Published var releaseURL: URL? = nil            // e.g. https://github.com/.../releases/tag/v1.1.0
    @Published var downloadURL: URL? = nil           // direct DMG link
    @Published var isChecking: Bool = false
    @Published var installState: InstallState = .idle

    enum InstallState: Equatable {
        case idle
        case downloading(progress: Double)
        case installing
        case failed(String)
    }

    // MARK: - Configuration
    private let apiURL = URL(string: "https://api.github.com/repos/heyderekj/binky/releases/latest")!
    private let throttleSeconds: TimeInterval = 60 * 60 * 24   // 24h

    // MARK: - GitHub API shape (only what we need)
    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    // MARK: - Public

    /// Outcome of a check. Only surfaced for manual checks — automatic ones
    /// stay silent so the app never nags the user on launch.
    enum CheckResult {
        case updateAvailable(version: String)
        case upToDate
        case failed
    }

    @discardableResult
    func check(manual: Bool = false, skipThrottle: Bool = false) async -> CheckResult {
        // Throttle background rechecks to once per 24h. Launch and manual checks bypass this.
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if !manual, !skipThrottle, last > 0, now - last < throttleSeconds {
            return .upToDate
        }

        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: apiURL, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Binky", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")

            let remoteTag = release.tag_name
            let remote = stripV(remoteTag)
            let current = currentVersion()

            // Only surface if remote is strictly newer.
            guard compareSemver(remote, current) == .orderedDescending else {
                // Up to date — clear any stale banner state.
                availableVersion = nil
                releaseURL = nil
                downloadURL = nil
                return .upToDate
            }

            // Prefer the zip for in-app install (no hdiutil, no Gatekeeper scan).
            // Fall back to DMG if zip isn't present (older releases).
            let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
                     ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                     ?? release.assets.first

            availableVersion = remote
            releaseURL = URL(string: release.html_url)
            downloadURL = asset.flatMap { URL(string: $0.browser_download_url) }
            return .updateAvailable(version: remote)
        } catch {
            // Silent failure is intentional for automatic checks. Callers can
            // decide whether to show UI for manual checks.
            return .failed
        }
    }

    // MARK: - In-app install

    /// Downloads the zip via URLSession (no quarantine), unzips with ditto,
    /// then replaces the running bundle **after** this process exits (shell script).
    /// Copying over `Bundle.main.bundleURL` while running hangs — never do that in-process.
    func downloadAndInstall() async {
        switch installState {
        case .idle, .failed:
            break
        default:
            return
        }
        guard let assetURL = downloadURL else {
            installState = .failed(
                String(localized: "No download URL for this release.", comment: "In-app updater: asset URL missing.")
            )
            return
        }
        installState = .downloading(progress: 0)

        do {
            // ── 1. Download ───────────────────────────────────────────
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let ext = assetURL.pathExtension.lowercased()
            let tempFile = tmp.appendingPathComponent("Binky-update.\(ext)")

            let (downloadedURL, _) = try await URLSession.shared.download(from: assetURL)
            _ = try? fm.removeItem(at: tempFile)
            try fm.moveItem(at: downloadedURL, to: tempFile)

            installState = .installing
            let dest = Bundle.main.bundleURL

            let stagedApp: URL
            var cleanupPaths: [String] = [tempFile.path]

            if ext == "zip" {
                let unzipDir = tmp.appendingPathComponent("Binky-update-extracted")
                _ = try? fm.removeItem(at: unzipDir)
                try await shell("/usr/bin/ditto", ["-xk", tempFile.path, unzipDir.path])
                let source = unzipDir.appendingPathComponent("Binky.app")
                guard fm.fileExists(atPath: source.path) else {
                    throw UpdateError.missingAppInArchive
                }
                stagedApp = source
                cleanupPaths.append(unzipDir.path)
            } else {
                let mountOut = try await shell(
                    "/usr/bin/hdiutil",
                    ["attach", tempFile.path, "-nobrowse", "-noautoopen", "-readonly"]
                )
                guard let mountPoint = parseHDIMountPoint(from: mountOut) else {
                    throw UpdateError.mountFailed
                }
                let mountedApp = URL(fileURLWithPath: mountPoint).appendingPathComponent("Binky.app")
                guard fm.fileExists(atPath: mountedApp.path) else {
                    _ = try? await shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
                    throw UpdateError.missingAppInArchive
                }
                let stagedCopy = tmp.appendingPathComponent("Binky-staged-\(UUID().uuidString).app")
                _ = try? fm.removeItem(at: stagedCopy)
                try await shell("/usr/bin/ditto", [mountedApp.path, stagedCopy.path])
                _ = try? await shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
                stagedApp = stagedCopy
                cleanupPaths.append(stagedCopy.path)
            }

            // Hard-stop if the downloaded bundle fails signature/identity checks.
            // Without this, anyone who hijacks the GitHub release pipeline gets a one-shot RCE
            // because the deferred installer also strips com.apple.quarantine.
            try await verifyStagedBundle(at: stagedApp)

            try launchDeferredBundleReplace(stagedApp: stagedApp, destination: dest, cleanupPaths: cleanupPaths)

            // Clear the sentinel now so a forced exit below doesn't produce a false crash report.
            DiagnosticsReporter.shared.clearSentinel()

            // Hard-exit fallback: NSApp.terminate's terminateLater reply sometimes
            // never fires when called from a Swift concurrency Task on @MainActor,
            // leaving the app stuck on "Installing…". A background thread guarantees
            // the process exits so the installer script can replace the bundle.
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: 4)
                exit(0)
            }

            NSApp.terminate(nil)

        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    /// Writes a shell script that waits for this process to quit, replaces the app bundle, cleans up, and opens the new app.
    ///
    /// Two safety properties this script must preserve:
    ///
    /// 1. **Never `rm -rf` a still-running app.** If the host process hasn't exited by the
    ///    deadline, abort cleanly — the user can retry later. The previous version proceeded
    ///    even if `kill -0` was still succeeding, which could corrupt memory-mapped pages of the
    ///    running bundle.
    ///
    /// 2. **The on-disk bundle is never in a destroyed-but-not-replaced state.** We rename the
    ///    existing app to a sibling backup path (atomic rename on the same volume) before laying
    ///    down the new one, and roll back the rename if `ditto` fails. The "no app at $DEST"
    ///    window shrinks from "however long ditto takes" to "one inode rename".
    private func launchDeferredBundleReplace(stagedApp: URL, destination: URL, cleanupPaths: [String]) throws {
        let fm = FileManager.default
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("binky-install-\(UUID().uuidString).sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        var lines: [String] = [
            "#!/bin/bash",
            // No set -e: we want `open` to run even if xattr exits non-zero, and we need to
            // restore on partial failure further down.
            //
            // Wait for the host PID to die. 30s is enough for any reasonable shutdown — the in-app
            // safety net (Thread.detachNewThread { sleep 4; exit(0) }) means we normally exit
            // within ~5s. If we hit the deadline anyway, the host is wedged in some unusual way
            // (sheet blocking terminate, deadlock) and we MUST NOT touch the running bundle.
            "deadline=$(( $(date +%s) + 30 ))",
            "while kill -0 \(pid) 2>/dev/null && [ $(date +%s) -lt $deadline ]; do sleep 0.2; done",
            "if kill -0 \(pid) 2>/dev/null; then",
            "  echo 'Binky updater: host process did not exit within 30s; aborting.' >&2",
            "  exit 2",
            "fi",
            "DEST=\(bashSingleQuotedPath(destination.path))",
            "STAGED=\(bashSingleQuotedPath(stagedApp.path))",
            // BACKUP must live next to DEST so /bin/mv stays atomic (same volume rename).
            "BACKUP=\"$DEST.binky-old-$$\"",
            "if [ -e \"$DEST\" ]; then",
            "  /bin/mv \"$DEST\" \"$BACKUP\" || exit 1",
            "fi",
            "if ! /usr/bin/ditto \"$STAGED\" \"$DEST\"; then",
            // Roll back: ditto failed, restore the original bundle if we backed it up.
            "  if [ -e \"$BACKUP\" ]; then /bin/mv \"$BACKUP\" \"$DEST\"; fi",
            "  exit 1",
            "fi",
            // Strip quarantine so Gatekeeper doesn't block the freshly-written bundle.
            "/usr/bin/xattr -rd com.apple.quarantine \"$DEST\" 2>/dev/null || true",
            // Backup is no longer needed.
            "if [ -e \"$BACKUP\" ]; then /bin/rm -rf \"$BACKUP\"; fi",
            // Unregister other Homebrew cask trees only (no mdfind/Spotlight — that could block
            // before `open -n`). `brew cleanup` still removes old Caskroom copies on disk.
            "shopt -s nullglob",
            "LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "D_CAN=$(/usr/bin/realpath \"$DEST\" 2>/dev/null || echo \"$DEST\")",
            "for other in /opt/homebrew/Caskroom/binky/*/Binky.app /usr/local/Caskroom/binky/*/Binky.app; do",
            "  [ -e \"$other\" ] || continue",
            "  O_CAN=$(/usr/bin/realpath \"$other\" 2>/dev/null || echo \"$other\")",
            "  [ \"$O_CAN\" = \"$D_CAN\" ] && continue",
            "  \"$LSREG\" -u \"$other\" 2>/dev/null || true",
            "done",
            "\"$LSREG\" -f \"$DEST\" 2>/dev/null || true",
        ]
        for p in cleanupPaths {
            lines.append("rm -rf \(bashSingleQuotedPath(p))")
        }
        // -n forces a new instance rather than connecting to any stale Launch Services entry.
        lines.append("/usr/bin/open -n \"$DEST\"")
        try lines.joined(separator: "\n").write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        try proc.run()
    }

    private func bashSingleQuotedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func parseHDIMountPoint(from mountOut: String) -> String? {
        guard let line = mountOut
            .components(separatedBy: "\n")
            .first(where: { $0.contains("/Volumes/") })?
            .components(separatedBy: "\t")
            .last
        else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum UpdateError: LocalizedError {
        case mountFailed
        case missingAppInArchive
        case signatureInvalid(String)
        case bundleIdentifierMismatch(String)
        case signingIdentityMismatch
        var errorDescription: String? {
            switch self {
            case .mountFailed:
                return String(localized: "Couldn't mount the update disk image.", comment: "In-app updater error.")
            case .missingAppInArchive:
                return String(localized: "The update didn’t contain Binky.app.", comment: "In-app updater error.")
            case .signatureInvalid(let detail):
                return String(localized: "The update’s code signature isn’t valid: \(detail)", comment: "In-app updater error: codesign --verify failed.")
            case .bundleIdentifierMismatch(let bid):
                return String(localized: "The update has an unexpected bundle identifier (\(bid)).", comment: "In-app updater error: CFBundleIdentifier did not match.")
            case .signingIdentityMismatch:
                return String(localized: "The update was signed by a different identity than the installed app.", comment: "In-app updater error: codesign team/identifier changed unexpectedly.")
            }
        }
    }

    // MARK: - Signature verification

    /// Validates the freshly-downloaded bundle before we let a deferred shell script overwrite the
    /// running app. Three independent checks must all pass:
    ///
    /// 1. `codesign --verify --deep --strict` reports the staged bundle's signature is intact
    ///    (catches tampering and broken bundles).
    /// 2. `CFBundleIdentifier` in the staged Info.plist equals the running app's bundle ID
    ///    (rejects "wrong app served from the same release").
    /// 3. The staged bundle's signing identity (`codesign -dv` Identifier + TeamIdentifier) matches
    ///    the running app's. This guards against a release that suddenly switched to a different
    ///    Developer ID — an attacker who got `gh` credentials cannot also produce a build signed
    ///    by Binky's existing key.
    private func verifyStagedBundle(at stagedApp: URL) async throws {
        // (1) Signature integrity.
        do {
            _ = try await shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--no-strict=resource", stagedApp.path])
        } catch let nsError as NSError {
            let detail = (nsError.userInfo[NSLocalizedDescriptionKey] as? String) ?? "exit \(nsError.code)"
            throw UpdateError.signatureInvalid(detail)
        }

        // (2) Bundle identifier match.
        let expectedBID = Bundle.main.bundleIdentifier ?? "com.binky.app"
        let stagedBID = readBundleIdentifier(at: stagedApp) ?? ""
        guard stagedBID == expectedBID else {
            throw UpdateError.bundleIdentifierMismatch(stagedBID)
        }

        // (3) Signing identity continuity.
        // Skipped only for the very first install where the running app is unsigned (no codesign info).
        let runningSig = (try? await codesignIdentity(for: Bundle.main.bundleURL)) ?? nil
        let stagedSig = try await codesignIdentity(for: stagedApp)
        if let running = runningSig {
            guard let staged = stagedSig else { throw UpdateError.signingIdentityMismatch }
            // Both team identifier AND signing identifier must match. Either one drifting is suspicious.
            guard running.team == staged.team, running.identifier == staged.identifier else {
                throw UpdateError.signingIdentityMismatch
            }
        }
    }

    private func readBundleIdentifier(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    private struct CodesignIdentity: Equatable {
        let identifier: String   // "Identifier=..." (often the bundle id)
        let team: String         // "TeamIdentifier=..." ("not set" for ad-hoc / unsigned)
    }

    private func codesignIdentity(for appURL: URL) async throws -> CodesignIdentity? {
        let out: String
        do {
            // codesign -dv writes to stderr. Our shell helper merges stderr into stdout.
            out = try await shell("/usr/bin/codesign", ["-dv", appURL.path])
        } catch {
            // Treat unsigned bundles (codesign exit 1) as "no identity" rather than fatal.
            return nil
        }
        var identifier = ""
        var team = ""
        for line in out.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let s = String(line)
            if s.hasPrefix("Identifier=") {
                identifier = String(s.dropFirst("Identifier=".count))
            } else if s.hasPrefix("TeamIdentifier=") {
                team = String(s.dropFirst("TeamIdentifier=".count))
            }
        }
        if identifier.isEmpty && team.isEmpty { return nil }
        return CodesignIdentity(identifier: identifier, team: team)
    }

    @discardableResult
    private func shell(_ path: String, _ args: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = pipe
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? "exit \(p.terminationStatus)"
                throw NSError(domain: "BinkyUpdater", code: Int(p.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8) ?? ""
        }.value
    }

    /// Dismiss the current banner for this version. Persists so it won't reappear
    /// until a strictly newer version is published.
    func dismissCurrent() {
        guard let v = availableVersion else { return }
        UserDefaults.standard.set(v, forKey: "dismissedUpdateVersion")
        availableVersion = nil
    }

    /// Whether the UI should show the banner (respects dismissed-version pref).
    func shouldShow(dismissedVersion: String) -> Bool {
        guard let v = availableVersion, !v.isEmpty else { return false }
        if dismissedVersion.isEmpty { return true }
        // Show if a newer version has shipped than the one the user dismissed.
        return compareSemver(v, dismissedVersion) == .orderedDescending
    }

    // MARK: - Version helpers

    private func currentVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return stripV(v)
    }

    private func stripV(_ s: String) -> String {
        var s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Compare semver-ish strings like "1.2.0" / "1.10.3". Non-numeric components
    /// are treated as 0, so pre-release suffixes lose to plain versions — fine for us.
    private func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").map { Int($0) ?? 0 }
        let bp = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(ap.count, bp.count)
        for i in 0..<count {
            let x = i < ap.count ? ap[i] : 0
            let y = i < bp.count ? bp[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }
}
