import Foundation

/// Mounts a DMG read-only, copies top-level `.app` bundles to an Applications folder, detaches, returns installed URLs.
enum DMGInstallerService: Sendable {

    enum InstallError: Error {
        case hdiutilFailed(Int32)
        case noMountPoint
        case noAppFound
        case copyFailed(String)
        case stagingFailed(String)
    }

    static func installApps(fromDmg dmg: URL, applicationsDestination: URL) throws -> [URL] {
        let fm = FileManager.default
        let plistData = try attachPlist(for: dmg)
        guard let mountPoint = parseMountPoint(fromPlistData: plistData) else {
            throw InstallError.noMountPoint
        }
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint, "-force"]
            try? detach.run()
            detach.waitUntilExit()
        }

        let mountURL = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let appBundles = try fm.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "app" }

        guard !appBundles.isEmpty else {
            throw InstallError.noAppFound
        }

        try fm.createDirectory(at: applicationsDestination, withIntermediateDirectories: true)

        var installed: [URL] = []
        for appURL in appBundles {
            let dest = applicationsDestination.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
            do {
                try atomicallyInstall(appURL: appURL, finalDestination: dest)
                installed.append(dest)
            } catch let e as InstallError {
                throw e
            } catch {
                throw InstallError.copyFailed(error.localizedDescription)
            }
        }
        return installed
    }

    /// Copies the new app to a sibling staging path, then atomically swaps it into place.
    /// Until the swap, the existing app is untouched — so a failure mid-copy never leaves the user
    /// without their installed app.
    ///
    /// `internal` (rather than `private`) so the test target can exercise the swap directly with
    /// arbitrary fixture directories instead of requiring a real DMG round-trip.
    static func atomicallyInstall(appURL: URL, finalDestination dest: URL) throws {
        let fm = FileManager.default
        let parent = dest.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".\(dest.lastPathComponent).binky-staged-\(UUID().uuidString)", isDirectory: true)

        // Make sure no leftover staging dir exists from a prior aborted run.
        if fm.fileExists(atPath: staging.path) {
            try? fm.removeItem(at: staging)
        }

        // Copy first. If this fails (disk full, permission denied), the old app at `dest` is untouched.
        do {
            try fm.copyItem(at: appURL, to: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw InstallError.stagingFailed(error.localizedDescription)
        }

        // Atomic swap: replaceItemAt removes the old item and moves staging into place in one step
        // (or rolls back if the OS-level move fails). When `dest` doesn't exist yet, fall back to a
        // plain move.
        do {
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: dest)
            }
        } catch {
            // Replacement failed mid-swap. Best effort: leave the original `dest` alone, drop staging.
            try? fm.removeItem(at: staging)
            throw InstallError.copyFailed(error.localizedDescription)
        }
    }

    private static func attachPlist(for dmg: URL) throws -> Data {
        let p = Process()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", "-plist", "-nobrowse", "-readonly", dmg.path]
        try p.run()
        // Read first to drain the pipe — `waitUntilExit()` after a `readDataToEndOfFile()` gives
        // us "drain then reap". Doing it the other way around can deadlock when hdiutil's plist
        // output exceeds the pipe buffer (rare but possible for DMGs with many partitions).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw InstallError.hdiutilFailed(p.terminationStatus)
        }
        return data
    }

    private static func parseMountPoint(fromPlistData data: Data) -> String? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        if let dict = obj as? [String: Any] {
            if let arr = dict["system-entities"] as? [[String: Any]] {
                for row in arr {
                    if let mp = row["mount-point"] as? String {
                        return mp
                    }
                }
            }
        }
        if let arr = obj as? [[String: Any]] {
            for row in arr {
                if let mp = row["mount-point"] as? String ?? row["MountPoint"] as? String {
                    return mp
                }
            }
        }
        return nil
    }
}
