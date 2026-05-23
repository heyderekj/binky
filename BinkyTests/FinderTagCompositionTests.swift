import XCTest
@testable import Binky

final class FinderTagCompositionTests: XCTestCase {

    func testBuiltInWhenMapsEmpty() {
        let tags = FinderTagComposer.compose(
            naturalCategory: .pdf,
            globalDefaults: [:],
            preset: nil,
            matchedRule: nil,
            appendNewSemanticTag: true
        )
        XCTAssertEqual(tags, ["Receipt", "New"])
    }

    func testGlobalOverridesBuiltIn() {
        let tags = FinderTagComposer.compose(
            naturalCategory: .pdf,
            globalDefaults: ["pdf": ["Invoice", "Tax"]],
            preset: nil,
            matchedRule: nil,
            appendNewSemanticTag: false
        )
        XCTAssertEqual(tags, ["Invoice", "Tax"])
    }

    func testPresetOverridesGlobal() {
        var preset = Inbox(name: "T")
        preset.finderTagDefaultsByCategory = ["images": ["Client"]]
        let tags = FinderTagComposer.compose(
            naturalCategory: .images,
            globalDefaults: ["images": ["Global"]],
            preset: preset,
            matchedRule: nil,
            appendNewSemanticTag: false
        )
        XCTAssertEqual(tags, ["Client"])
    }

    func testExplicitEmptyCategoryMapMeansNoCategoryTags() {
        var preset = Inbox(name: "T")
        preset.finderTagDefaultsByCategory = ["pdf": []]
        let tags = FinderTagComposer.compose(
            naturalCategory: .pdf,
            globalDefaults: ["pdf": ["Ignored"]],
            preset: preset,
            matchedRule: nil,
            appendNewSemanticTag: false
        )
        XCTAssertEqual(tags, [])
    }

    func testReplaceCategoryDefaultPolicy() {
        var preset = Inbox(name: "T")
        preset.customFinderTags = ["Profile"]
        let rule = SortRule(
            id: UUID(),
            isEnabled: true,
            name: "R",
            matchExtensions: [],
            nameContains: "",
            fileKindFilter: .any,
            minSizeBytes: nil,
            maxSizeBytes: nil,
            dateAddedPredicate: nil,
            destinationRelativePath: "X",
            renameStyle: .none,
            renameTemplate: "{date}",
            addedTags: ["Extra"],
            finderTagPolicy: .replaceCategoryDefault,
            categoryDefaultReplacementTags: ["FolderA"]
        )
        let tags = FinderTagComposer.compose(
            naturalCategory: .pdf,
            globalDefaults: ["pdf": ["Ignored"]],
            preset: preset,
            matchedRule: rule,
            appendNewSemanticTag: false
        )
        XCTAssertEqual(tags, ["FolderA", "Profile", "Extra"])
    }

    func testSortRuleDecodesWhenOmittingNewFinderTagKeys() throws {
        let encoder = JSONEncoder()
        let baseline = SortRule.fresh(order: 1)
        var data = try encoder.encode(baseline)
        var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw.removeValue(forKey: "finderTagPolicy")
        raw.removeValue(forKey: "categoryDefaultReplacementTags")
        data = try JSONSerialization.data(withJSONObject: raw)
        let decoded = try JSONDecoder().decode(SortRule.self, from: data)
        XCTAssertEqual(decoded.finderTagPolicy, .additive)
        XCTAssertEqual(decoded.categoryDefaultReplacementTags, [])
    }

    func testInboxDecodesWhenOmittingFinderTagDefaultsKey() throws {
        let encoder = JSONEncoder()
        let baseline = Inbox(name: "Legacy")
        var data = try encoder.encode(baseline)
        var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw.removeValue(forKey: "finderTagDefaultsByCategory")
        data = try JSONSerialization.data(withJSONObject: raw)
        let decoded = try JSONDecoder().decode(Inbox.self, from: data)
        XCTAssertEqual(decoded.finderTagDefaultsByCategory, [:])
    }
}
