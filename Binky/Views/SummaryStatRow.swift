import SwiftUI

/// Icon + label row aligned with batch summary and confirmation sheets (14pt medium SF Symbols).
struct SummaryStatRow: View {
    let icon: String
    let text: String
    var textSecondary: Bool = false
    var subheadline: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(subheadline ? .subheadline : .body)
                .foregroundStyle(textSecondary ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One leading icon with stacked secondary lines (avoids repeating the same symbol for multi-line policy copy).
struct SummaryPolicyGroup: View {
    let icon: String
    let lines: [String]
    var textSecondary: Bool = true
    var subheadline: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(subheadline ? .subheadline : .body)
                        .foregroundStyle(textSecondary ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One horizontal row of per-type counts (icon + number), separated by middle dots.
/// Leading column matches `SummaryStatRow` so the strip lines up with other summary rows.
struct SummaryMediaCountStrip: View {
    let segments: [(icon: String, count: Int)]
    var accessibilitySummary: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Text(verbatim: "\u{00B7}")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: segment.icon)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(verbatim: "\(segment.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}
