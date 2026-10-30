import SwiftUI

/// Shared brand tint — aligns with [binkyfiles.com](https://binkyfiles.com) `--brand` / `#e3366e`.
let binkyTintColor = Color(red: 227 / 255, green: 54 / 255, blue: 110 / 255)

// MARK: - Section chrome (sidebar + Settings)

/// Matches grouped settings subsection titles: icon + semibold body, in text styles so they scale.
func settingsSectionHeading(icon: String, title: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 6)
}

func settingsSubHeader(icon: String, _ title: String) -> some View {
    settingsSectionHeading(icon: icon, title: title)
}

struct SettingsSectionDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}

func settingsHelperText(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
}
