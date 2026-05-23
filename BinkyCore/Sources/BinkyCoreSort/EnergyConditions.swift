import BinkyCoreShared
import Foundation

// MARK: - User-configurable batch threshold

public enum SortEnergy {
    private static let defaultBigBatchThreshold = 200

    /// File count threshold from Settings → General → Energy, or default 200 when unset.
    public static var bigBatchFileCount: Int {
        let d = UserDefaults.standard
        let key = EnergySettingsKey.bigBatchThreshold
        guard d.object(forKey: key) != nil else { return defaultBigBatchThreshold }
        let v = d.integer(forKey: key)
        return min(max(v, 50), 10_000)
    }
}

// MARK: - Preferences (read off MainActor; keys match `BinkyPreferences` `@AppStorage`)

private enum EnergyPreferenceDefaults {
    static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    static var pauseOnLowPowerMode: Bool {
        bool(forKey: EnergySettingsKey.pauseOnLowPowerMode, defaultValue: true)
    }

    static var pauseOnThermalCritical: Bool {
        bool(forKey: EnergySettingsKey.pauseOnThermalCritical, defaultValue: true)
    }

    static var throttleProfile: EnergyThrottleProfile {
        let raw = UserDefaults.standard.string(forKey: EnergySettingsKey.throttleProfile) ?? EnergyThrottleProfile.auto.rawValue
        return EnergyThrottleProfile(rawValue: raw) ?? .auto
    }
}

/// Thermal / Low Power Mode awareness for sort throttling. Thread-safe for use from detached tasks.
public final class EnergyConditions: @unchecked Sendable {
    public static let shared = EnergyConditions()

    private let lock = NSLock()
    private var thermalState: ProcessInfo.ThermalState
    private var lowPowerMode: Bool
    /// Each waiter is identified by a UUID so the cancellation handler can pop a specific
    /// continuation rather than draining everyone. Without this, `withCheckedContinuation`
    /// suspended inside `waitUntilOK` could leak forever when the surrounding sort Task is
    /// cancelled — the continuation would never resume and the task became a zombie.
    private var waiters: [(id: UUID, cont: CheckedContinuation<Void, Never>)] = []

    private init() {
        let pi = ProcessInfo.processInfo
        thermalState = pi.thermalState
        lowPowerMode = pi.isLowPowerModeEnabled

        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    public var shouldPauseFully: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFullPauseUnlocked
    }

    /// Which hold to show in sort progress UI when `shouldPauseFully` is true.
    public func energyHoldKindForProgressUI() -> SortEnergyHoldKind {
        let pi = ProcessInfo.processInfo
        if pi.isLowPowerModeEnabled, EnergyPreferenceDefaults.pauseOnLowPowerMode {
            return .lowPower
        }
        if pi.thermalState == .critical, EnergyPreferenceDefaults.pauseOnThermalCritical {
            return .thermal
        }
        return .thermal
    }

    /// Inter-file delay for large batches when not in full pause.
    public func interFileSleepNanos(batchSize: Int) -> UInt64 {
        guard batchSize >= SortEnergy.bigBatchFileCount else { return 0 }
        lock.lock()
        let thermal = thermalState
        lock.unlock()

        let profile = EnergyPreferenceDefaults.throttleProfile
        switch profile {
        case .auto:
            return sleepNanosAuto(thermal: thermal)
        case .gentle:
            return sleepNanosGentle(thermal: thermal)
        case .aggressive:
            return sleepNanosAggressive(thermal: thermal)
        }
    }

    private func sleepNanosAuto(thermal: ProcessInfo.ThermalState) -> UInt64 {
        switch thermal {
        case .nominal:
            return 0
        case .fair:
            return 10_000_000
        case .serious:
            return 50_000_000
        case .critical:
            return 0
        @unknown default:
            return 0
        }
    }

    private func sleepNanosGentle(thermal: ProcessInfo.ThermalState) -> UInt64 {
        switch thermal {
        case .nominal:
            return 0
        case .fair:
            return 25_000_000
        case .serious:
            return 125_000_000
        case .critical:
            return 0
        @unknown default:
            return 0
        }
    }

    private func sleepNanosAggressive(thermal: ProcessInfo.ThermalState) -> UInt64 {
        switch thermal {
        case .nominal:
            return 0
        case .fair:
            return 5_000_000
        case .serious:
            return 25_000_000
        case .critical:
            return 0
        @unknown default:
            return 0
        }
    }

    public func waitUntilOK() async {
        while shouldPauseFully {
            if Task.isCancelled { return }
            let waiterID = UUID()
            await withTaskCancellationHandler(
                operation: {
                    await withCheckedContinuation { continuation in
                        lock.lock()
                        if !isFullPauseUnlocked {
                            // State already cleared between the loop check and now — resume right away.
                            lock.unlock()
                            continuation.resume()
                        } else if Task.isCancelled {
                            // Cancellation raced with our enqueue; don't suspend.
                            lock.unlock()
                            continuation.resume()
                        } else {
                            waiters.append((id: waiterID, cont: continuation))
                            lock.unlock()
                        }
                    }
                },
                onCancel: { [weak self] in
                    self?.cancelWaiter(id: waiterID)
                }
            )
        }
    }

    private func cancelWaiter(id waiterID: UUID) {
        lock.lock()
        let cont: CheckedContinuation<Void, Never>?
        if let idx = waiters.firstIndex(where: { $0.id == waiterID }) {
            cont = waiters.remove(at: idx).cont
        } else {
            cont = nil
        }
        lock.unlock()
        cont?.resume()
    }

    private var isFullPauseUnlocked: Bool {
        let lpmHolds = lowPowerMode && EnergyPreferenceDefaults.pauseOnLowPowerMode
        let thermalHolds = thermalState == .critical && EnergyPreferenceDefaults.pauseOnThermalCritical
        return lpmHolds || thermalHolds
    }

    private func refresh() {
        let pi = ProcessInfo.processInfo
        let newThermal = pi.thermalState
        let newLowPower = pi.isLowPowerModeEnabled

        lock.lock()
        let wasFullPause = isFullPauseUnlocked
        thermalState = newThermal
        lowPowerMode = newLowPower
        let isFullPause = isFullPauseUnlocked

        let waitersCopy: [(id: UUID, cont: CheckedContinuation<Void, Never>)]
        if !isFullPause {
            waitersCopy = waiters
            waiters.removeAll()
        } else {
            waitersCopy = []
        }
        lock.unlock()

        for entry in waitersCopy {
            entry.cont.resume()
        }

        if wasFullPause && !isFullPause {
            NotificationCenter.default.post(name: Notification.Name("binkyEnergyHoldReleased"), object: nil)
        }
    }
}
