import Foundation

final class FolderWatcher: ObservableObject {
    var onNewFiles: (([URL]) -> Void)?
    private var stream: FSEventStreamRef?

    /// FSEvents callbacks do file-existence and resource-value lookups before forwarding the URL
    /// list to consumers. We dispatch the stream to a dedicated background queue so those
    /// synchronous filesystem stat calls never block the main thread when the watched folder
    /// suddenly produces a burst of events (zip extraction, large download finishing, etc).
    private static let dispatchQueue = DispatchQueue(
        label: "com.binky.folderwatcher",
        qos: .utility
    )

    /// Subscribes to filesystem changes under one or more directories (`paths` must be non-empty).
    ///
    /// **Lifetime contract:** The caller must keep a strong reference to this `FolderWatcher`
    /// instance for as long as the stream is active. The FSEvents context uses
    /// `Unmanaged.passUnretained` — the watcher does NOT retain itself. If the owning object
    /// drops its reference without calling `stop()`, `deinit` will tear down the stream safely.
    func start(paths: [String]) {
        stop()
        let normalized = paths
            .map { ($0 as NSString).standardizingPath }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }

        // passUnretained: the caller owns our lifetime. No retain cycle, no leaked watcher if
        // the owner is deallocated (deinit calls stop() which invalidates the stream before the
        // pointer could dangle).
        let unretained = Unmanaged.passUnretained(self).toOpaque()
        var ctx = FSEventStreamContext(version: 0, info: unretained,
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            guard let paths = cfPaths as? [String] else { return }
            let now = Date()
            let fm = FileManager.default
            let urls = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { url in
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
                    return true
                }
                .filter { url in
                    guard let rv = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
                          let created = rv.creationDate else { return false }
                    let modified = rv.contentModificationDate ?? created
                    let ref = modified > created ? modified : created
                    return now.timeIntervalSince(ref) < 30
                }
            guard !urls.isEmpty else { return }
            DispatchQueue.main.async { watcher.onNewFiles?(urls) }
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            normalized as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard stream != nil else { return }
        FSEventStreamSetDispatchQueue(stream!, Self.dispatchQueue)
        FSEventStreamStart(stream!)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit { stop() }
}
