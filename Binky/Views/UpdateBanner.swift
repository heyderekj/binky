// UpdateBanner.swift — update card at the bottom of the sidebar when UpdateChecker finds a newer
// release on GitHub. Same place and shape as Slinky's and Dinky's.

import SwiftUI
import AppKit

struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: BinkyPreferences
    /// In-flight work a relaunch would drop; asks first when non-zero.
    var itemCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Binky \(updater.availableVersion ?? "") is available", comment: "Update card title; version number."))
                        .font(.callout.weight(.semibold))
                    status
                }
                Spacer(minLength: 4)
                if !isWorking {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            updater.installState = .idle
                            prefs.dismissedUpdateVersion = updater.availableVersion ?? ""
                            updater.dismissCurrent()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Not now", comment: "Tooltip for dismissing the update card."))
                }
            }

            HStack(spacing: 8) {
                Button(isFailed
                       ? String(localized: "Retry", comment: "Update card after failure.")
                       : String(localized: "Install", comment: "Update card primary button.")) {
                    install()
                }
                .glassProminentButton()
                .controlSize(.small)
                .disabled(isWorking)

                if let release = updater.releaseURL {
                    Link(String(localized: "What’s New", comment: "Update card link to release notes."), destination: release)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        // Not glass: the sidebar it sits in already is.
        .card(cornerRadius: 14)
    }

    @ViewBuilder
    private var status: some View {
        switch updater.installState {
        case .idle:
            EmptyView()
        case .downloading:
            Text(String(localized: "Downloading…", comment: "Update banner status.")).font(.caption).foregroundStyle(.secondary)
        case .installing:
            Text(String(localized: "Installing…", comment: "Update banner status.")).font(.caption).foregroundStyle(.secondary)
        case .failed(let msg):
            Text(String(localized: "Update failed: \(msg)", comment: "Update banner error; argument is message."))
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isWorking: Bool {
        switch updater.installState {
        case .downloading, .installing: return true
        default: return false
        }
    }

    private var isFailed: Bool {
        if case .failed = updater.installState { return true }
        return false
    }

    private func install() {
        if itemCount > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "Install update now?", comment: "Alert when installing with queued files.")
            alert.informativeText = String(localized: "Your current results will be cleared when Binky relaunches.", comment: "Alert detail for install with queue.")
            alert.addButton(withTitle: String(localized: "Install", comment: "Alert confirm button."))
            alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert cancel button."))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task { await updater.downloadAndInstall() }
    }
}
