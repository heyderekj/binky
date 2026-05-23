import BinkyCoreShared
import Foundation

/// Central precedence for Finder tags at sort time (shared GUI + CLI + tests).
public enum FinderTagComposer {

    /// Resolves tags in this order:
    /// 1. Category defaults: preset map → global map → built-in ``FileSortCategory/semanticTagHint`` (unless a rule replaces this layer).
    /// 2. Matched rule with ``SortRuleFinderTagPolicy/replaceCategoryDefault`` replaces the category-default layer with ``SortRule/categoryDefaultReplacementTags``.
    /// 3. Routine ``Inbox/customFinderTags`` (all sorts in that profile context).
    /// 4. Rule ``SortRule/addedTags``.
    /// 5. Optional literal `"New"` when enabled.
    public static func compose(
        naturalCategory: FileSortCategory,
        globalDefaults: [String: [String]],
        preset: Inbox?,
        matchedRule: SortRule?,
        appendNewSemanticTag: Bool
    ) -> [String] {
        var tags: [String] = []

        if let rule = matchedRule, rule.finderTagPolicy == .replaceCategoryDefault {
            tags.append(contentsOf: normalizedTags(rule.categoryDefaultReplacementTags))
        } else {
            tags.append(contentsOf: categoryDefaultTags(
                naturalCategory: naturalCategory,
                globalDefaults: globalDefaults,
                preset: preset
            ))
        }

        if let preset {
            tags.append(contentsOf: normalizedTags(preset.customFinderTags))
        }
        if let matchedRule {
            tags.append(contentsOf: normalizedTags(matchedRule.addedTags))
        }
        if appendNewSemanticTag {
            tags.append("New")
        }
        return tags
    }

    private static func categoryDefaultTags(
        naturalCategory: FileSortCategory,
        globalDefaults: [String: [String]],
        preset: Inbox?
    ) -> [String] {
        let key = naturalCategory.rawValue
        if let preset, let layer = preset.finderTagDefaultsByCategory[key] {
            return normalizedTags(layer)
        }
        if let layer = globalDefaults[key] {
            return normalizedTags(layer)
        }
        return [naturalCategory.semanticTagHint]
    }

    private static func normalizedTags(_ raw: [String]) -> [String] {
        raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
