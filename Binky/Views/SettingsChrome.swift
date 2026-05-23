import SwiftUI

/// Shared brand tint — aligns with [binkyfiles.com](https://binkyfiles.com) `--brand` / `#e3366e`.
///
/// Uses an adaptive color that's slightly desaturated in dark mode to maintain contrast against
/// dark backgrounds. If an Asset Catalog color named "BinkyBrand" exists, it takes precedence
/// (allows designers to fine-tune per-appearance without a code change).
let binkyTintColor: Color = {
    // Prefer Asset Catalog color if present (allows future fine-tuning without code changes).
    if let _ = NSColor(named: "BinkyBrand") {
        return Color("BinkyBrand")
    }
    // Fallback: adaptive color that's slightly lighter in dark mode for contrast.
    return Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // Dark mode: lighten slightly for contrast against dark backgrounds.
            return NSColor(red: 237 / 255, green: 84 / 255, blue: 130 / 255, alpha: 1)
        } else {
            return NSColor(red: 227 / 255, green: 54 / 255, blue: 110 / 255, alpha: 1)
        }
    })
}()

// MARK: - Section chrome (sidebar + Settings)

/// Matches grouped settings subsection titles: icon + 13pt semibold.
func settingsSectionHeading(icon: String, title: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
        Text(title)
            .font(.system(size: 13, weight: .semibold))
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

/// Helper text below settings controls. Uses `.secondary` at 11pt instead of the previous
/// `.tertiary` at 10pt — the old style failed WCAG AA contrast in both light and dark mode.
func settingsHelperText(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
}

// MARK: - Unified button / link styles

/// Standard "link-style" button used throughout Binky for inline text actions. Replaces the
/// previous three inconsistent patterns (`.plain` + tint, `.borderless` + tint, `.plain` +
/// `.secondary` + `.underline`). Use this for any non-primary action that should look like a
/// tappable text link.
struct BinkyLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(configuration.isPressed ? binkyTintColor.opacity(0.6) : binkyTintColor)
    }
}

extension ButtonStyle where Self == BinkyLinkButtonStyle {
    /// Inline text-link appearance: brand tint, no border, dims on press.
    static var binkyLink: BinkyLinkButtonStyle { BinkyLinkButtonStyle() }
}
