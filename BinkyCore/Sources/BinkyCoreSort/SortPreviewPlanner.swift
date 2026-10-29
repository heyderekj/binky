import BinkyCoreShared
import Foundation

public enum SortPreviewPlanner {

    nonisolated public static func preview(
        files urls: [URL],
        snapshot: SortPreferencesSnapshot,
        rootOverride: [URL: URL] = [:]
    ) async -> [SortPreviewEntry] {
        let fm = FileManager.default
        var renameCounter = 1
        var out: [SortPreviewEntry] = []

        for raw in urls {
            let standardized = raw.standardizedFileURL
            guard standardized.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard isAppBundleURL(standardized) else { continue }
            }

            if looksTransientIncomplete(standardized) {
                let sum = String(localized: "Skipped — looks like an incomplete download.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: "—",
                    summary: sum,
                    whyLine: String(localized: "Incomplete download — skipped for now.", comment: "Preview why: transient."),
                    category: .review,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .skippedTransient
                ))
                continue
            }

            if SortRulesEvaluator.isExcluded(url: standardized, snapshot: snapshot) {
                let sum = String(localized: "Excluded — matches your ignore list.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: "—",
                    summary: sum,
                    whyLine: String(localized: "On your ignore list.", comment: "Preview why: excluded."),
                    category: .misc,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .skippedExcluded
                ))
                continue
            }

            if fileURLMatchesGlobalSkipTags(standardized, snapshot: snapshot) {
                let sum = String(localized: "Skipped — protected Finder tag.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: "—",
                    summary: sum,
                    whyLine: String(localized: "This file has a tag on your “never sort” list.", comment: "Preview why: skip tag."),
                    category: .misc,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .skippedProtectedTag
                ))
                continue
            }

            let signals = SortRulesEvaluator.loadSignals(url: standardized)
                ?? SortRulesEvaluator.FileSignals(
                    ext: standardized.pathExtension.lowercased(),
                    baseName: standardized.lastPathComponent,
                    byteSize: 0,
                    addedToDirectoryDate: nil,
                    creationDate: nil,
                    modificationDate: nil,
                    originHosts: WhereFromsReader.originHosts(forFileAt: standardized)
                )

            let fileTags = FinderTagApplicator.readTagNames(for: standardized)

            let (defaultRoot, presets) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let activeRules = activeSortRulesForSnapshot(snapshot: snapshot, presets: presets)

            func composePlannedTags(naturalCategory: FileSortCategory, rule: SortRule?) -> [String] {
                FinderTagComposer.compose(
                    naturalCategory: naturalCategory,
                    globalDefaults: snapshot.finderTagDefaultsByCategory,
                    preset: presets.first,
                    matchedRule: rule,
                    appendNewSemanticTag: snapshot.sortAppendNewSemanticTagEnabled
                )
            }

            var pendingDigestSHA: String?
            if snapshot.sortDuplicateMode != .off {
                if let digestTry = try? FileHashStore.shared.digestFile(at: standardized) {
                    pendingDigestSHA = digestTry.sha256
                    let lookup = FileHashStore.shared.lookup(
                        sha256: digestTry.sha256,
                        perceptual: digestTry.perceptual,
                        isImage: digestTry.isImage
                    )
                    if lookup.isByteDuplicate || lookup.isNearImageDuplicate {
                        let destLabel: String
                        switch snapshot.sortDuplicateMode {
                        case .off:
                            destLabel = "—"
                        case .moveToTrash:
                            destLabel = String(localized: "Trash", comment: "Sort preview duplicate.")
                        case .moveToDuplicates:
                            destLabel = destinationDisplayLabelForSort(
                                root: inboxRoot,
                                destinationDir: StarterDestinations.directory(for: .duplicates, root: inboxRoot)
                            )
                        }
                        let sum = String(localized: "Duplicate — would skip per your settings.", comment: "Sort preview.")
                        out.append(SortPreviewEntry(
                            id: UUID(),
                            sourcePath: standardized.path,
                            proposedDestinationPath: destLabel,
                            summary: sum,
                            whyLine: String(localized: "Already got one.", comment: "Preview why: duplicate."),
                            category: .duplicates,
                            matchedRuleName: nil,
                            addedTags: [],
                            planDisposition: .skippedDuplicate
                        ))
                        continue
                    }
                }
            }

            let taxonomyCategory = FileClassification.categorize(url: standardized)
            let ext = signals.ext
            let isImageFile = isRasterImageExtensionForSort(ext)
            let needsInspection =
                (snapshot.sortDetectReceiptsEnabled && (ext == "pdf" || isImageFile))
                || SortRulesEvaluator.anyRuleRequiresContentInspection(activeRules)
                || (snapshot.sortSmartScreenshotNamesEnabled && taxonomyCategory == .screenshots && isImageFile)

            let inspection: ContentInspector.ContentInspectionResult
            if needsInspection {
                inspection = await ContentInspector.inspect(
                    for: standardized,
                    signals: signals,
                    snapshot: snapshot,
                    contentIdentitySHA256: pendingDigestSHA,
                    wantsVisualTraits: SortRulesEvaluator.anyRuleRequiresVisualCategory(activeRules)
                )
            } else {
                inspection = ContentInspector.emptyInspection
            }

            let contentInput = inspection.ruleMatchInput
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals, content: contentInput, fileTags: fileTags)
            let originHost = signals.originHosts.first

            let useReceiptAutoRoute =
                matchedRule == nil
                && snapshot.sortDetectReceiptsEnabled
                && inspection.isReceiptLike
                && (ext == "pdf" || isImageFile)

            let naturalCategoryForTags: FileSortCategory =
                if let mr = matchedRule, mr.matchAction != .moveToTrash {
                    taxonomyCategory
                } else if useReceiptAutoRoute {
                    .receipts
                } else {
                    taxonomyCategory
                }

            if let rule = matchedRule, rule.matchAction == .moveToTrash {
                let trashSummary = String.localizedStringWithFormat(
                    String(localized: "Rule “%@” → Trash", comment: "Sort preview row: rule sends file to Trash."),
                    rule.name
                )
                let whyTrash: String
                if rule.contentMatch.kind != .none {
                    whyTrash = String.localizedStringWithFormat(
                        String(localized: "Matched by content · rule “%@”.", comment: "Preview why: trash via content rule."),
                        rule.name
                    )
                } else if let host = originHost, !host.isEmpty, !rule.originDomains.isEmpty {
                    whyTrash = String.localizedStringWithFormat(
                        String(localized: "Rule “%1$@” · from %2$@.", comment: "Preview why: trash rule + origin."),
                        rule.name,
                        host
                    )
                } else {
                    whyTrash = String.localizedStringWithFormat(
                        String(localized: "Rule “%@”.", comment: "Preview why: named trash rule."),
                        rule.name
                    )
                }
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: String(localized: "Trash", comment: "Sort preview: destination is Trash."),
                    summary: trashSummary,
                    whyLine: whyTrash,
                    category: .misc,
                    matchedRuleName: rule.name,
                    addedTags: [],
                    planDisposition: .wouldTrash
                ))
                continue
            }

            let dominantOCRSlug: String? = inspection.dominantOCRLine.flatMap {
                let s = SortRulesEvaluator.slugifyForRenameToken(from: $0, maxLen: 60)
                return s.isEmpty ? nil : s
            }

            let category: FileSortCategory
            let destinationDir: URL
            var preferredFilename: String

            if let rule = matchedRule, rule.matchAction != .moveToTrash {
                category = SortRulesEvaluator.customRuleTagCategory
                if rule.matchAction == .renameInPlace {
                    destinationDir = standardized.deletingLastPathComponent().standardizedFileURL
                } else if rule.matchAction == .tagFanout {
                    destinationDir = SortRulesEvaluator.tagFanoutDestinationDirectory(
                        rule: rule,
                        inboxRoot: inboxRoot,
                        fileTags: fileTags,
                        priority: combinedTagFanoutPriority(presets: presets)
                    )
                } else {
                    destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                }
                preferredFilename = SortRulesEvaluator.renamedFilename(
                    originalURL: standardized,
                    rule: rule,
                    renameCounter: renameCounter,
                    originHost: originHost,
                    ocrSlug: dominantOCRSlug,
                    vendorSlug: inspection.vendorSlug,
                    amountSlug: inspection.amountSlug
                )
                if rule.renameStyle != .none { renameCounter += 1 }
            } else if useReceiptAutoRoute {
                category = .receipts
                let vendorFolder = inspection.vendorSlug ?? "Receipt"
                destinationDir = StarterDestinations.directory(for: .receipts, root: inboxRoot)
                    .appendingPathComponent(vendorFolder, isDirectory: true)
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withFullDate]
                let dateStr = df.string(from: Date())
                let amt = inspection.amountSlug ?? "0.00"
                preferredFilename = "\(vendorFolder) — \(dateStr) — \(amt).\(ext)"
            } else {
                category = taxonomyCategory
                destinationDir = StarterDestinations.directory(for: category, root: inboxRoot)
                preferredFilename = standardized.lastPathComponent
                if category == .screenshots, snapshot.sortSmartScreenshotNamesEnabled, isImageFile,
                   let smart = await ContentInspector.preferredSmartScreenshotName(
                       fileURL: standardized,
                       naturalCategory: category,
                       snapshot: snapshot,
                       signals: signals,
                       contentIdentitySHA256: pendingDigestSHA
                   ) {
                    preferredFilename = smart
                }
            }

            if let rule = matchedRule, rule.matchAction == .zipToDestination {
                let zipStem = standardized.deletingPathExtension().lastPathComponent
                let zipPreferred = "\(zipStem).zip"
                let zipTarget = SortCollision.uniquify(destinationDirectory: destinationDir, preferredFilename: zipPreferred)
                let label = destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destinationDir)
                let summary = String.localizedStringWithFormat(
                    String(localized: "Rule “%1$@” · zip → %2$@", comment: "Sort preview; zip rule."),
                    rule.name,
                    label
                )
                let whyLineZip: String
                if rule.contentMatch.kind != .none {
                    whyLineZip = String.localizedStringWithFormat(
                        String(localized: "Matched by content · sent by “%@”.", comment: "Preview why: content rule."),
                        rule.name
                    )
                } else if let host = originHost, !host.isEmpty, !rule.originDomains.isEmpty {
                    whyLineZip = String.localizedStringWithFormat(
                        String(localized: "Sent by “%1$@” · from %2$@.", comment: "Preview why: rule + origin."),
                        rule.name,
                        host
                    )
                } else {
                    whyLineZip = String.localizedStringWithFormat(
                        String(localized: "Sent by “%@”.", comment: "Preview why: named rule."),
                        rule.name
                    )
                }
                let tagsZip = composePlannedTags(naturalCategory: naturalCategoryForTags, rule: matchedRule)
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: zipTarget.path,
                    summary: summary,
                    whyLine: whyLineZip,
                    category: category,
                    matchedRuleName: rule.name,
                    addedTags: tagsZip,
                    planDisposition: .wouldZip
                ))
                continue
            }

            if standardized.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL,
               standardized.lastPathComponent == preferredFilename {
                let sum = String(localized: "Already in place — no move.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: destinationDir.path,
                    summary: sum,
                    whyLine: String(localized: "Already in the right place.", comment: "Preview why: no move."),
                    category: category,
                    matchedRuleName: matchedRule?.name,
                    addedTags: [],
                    planDisposition: .keptInPlace
                ))
                continue
            }

            let target = SortCollision.uniquify(destinationDirectory: destinationDir, preferredFilename: preferredFilename)
            let label = destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destinationDir)
            let summary: String
            if let rule = matchedRule {
                if rule.matchAction == .renameInPlace {
                    summary = String.localizedStringWithFormat(
                        String(localized: "Rule “%1$@” · rename here → %2$@", comment: "Sort preview; rename-in-place rule."),
                        rule.name,
                        target.lastPathComponent
                    )
                } else {
                    summary = String.localizedStringWithFormat(
                        String(localized: "Rule “%1$@” → %2$@", comment: "Sort preview; rule name and destination."),
                        rule.name,
                        label
                    )
                }
            } else if useReceiptAutoRoute {
                summary = String.localizedStringWithFormat(
                    String(localized: "Receipt → %1$@", comment: "Sort preview; receipt destination."),
                    label
                )
            } else {
                summary = String.localizedStringWithFormat(
                    String(localized: "Automatic sort → %1$@", comment: "Sort preview; destination label."),
                    label
                )
            }

            let whyLineResolved: String
            if let rule = matchedRule {
                if rule.contentMatch.kind != .none {
                    whyLineResolved = String.localizedStringWithFormat(
                        String(localized: "Matched by content · sent by “%@”.", comment: "Preview why: content rule."),
                        rule.name
                    )
                } else if let host = originHost, !host.isEmpty, !rule.originDomains.isEmpty {
                    whyLineResolved = String.localizedStringWithFormat(
                        String(localized: "Sent by “%1$@” · from %2$@.", comment: "Preview why: rule + origin."),
                        rule.name,
                        host
                    )
                } else {
                    whyLineResolved = String.localizedStringWithFormat(
                        String(localized: "Sent by “%@”.", comment: "Preview why: named rule."),
                        rule.name
                    )
                }
            } else if useReceiptAutoRoute {
                whyLineResolved = String(localized: "Looks like a receipt.", comment: "Preview why: receipt heuristic.")
            } else if let host = originHost, !host.isEmpty {
                whyLineResolved = String.localizedStringWithFormat(
                    String(localized: "By file type · from %@.", comment: "Preview why: taxonomy + host."),
                    host
                )
            } else {
                whyLineResolved = String(localized: "By file type.", comment: "Preview why: taxonomy only.")
            }

            let tagsMove = composePlannedTags(naturalCategory: naturalCategoryForTags, rule: matchedRule)
            out.append(SortPreviewEntry(
                id: UUID(),
                sourcePath: standardized.path,
                proposedDestinationPath: target.path,
                summary: summary,
                whyLine: whyLineResolved,
                category: category,
                matchedRuleName: matchedRule?.name,
                addedTags: tagsMove,
                planDisposition: .wouldMove
            ))
        }
        return out
    }

    nonisolated public static func preview(
        work: SortSweepWorkItems,
        snapshot: SortPreferencesSnapshot,
        rootOverride: [URL: URL] = [:]
    ) async -> [SortPreviewEntry] {
        var rows = await preview(files: work.fileURLs, snapshot: snapshot, rootOverride: rootOverride)
        guard snapshot.sortMoveLooseFoldersEnabled else { return rows }
        rows.append(contentsOf: looseFolderPreviewEntries(work.looseFolderURLs, snapshot: snapshot, rootOverride: rootOverride))
        return rows
    }

    private nonisolated static func looseFolderPreviewEntries(
        _ folderURLs: [URL],
        snapshot: SortPreferencesSnapshot,
        rootOverride: [URL: URL]
    ) -> [SortPreviewEntry] {
        let fm = FileManager.default
        let rel = snapshot.resolvedLooseFoldersRelativePath()
        var out: [SortPreviewEntry] = []

        for raw in folderURLs {
            let standardized = raw.standardizedFileURL
            if looksTransientIncomplete(standardized) {
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: "—",
                    summary: String(localized: "Skipped — looks like a transient download folder.", comment: "Sort preview loose folder."),
                    whyLine: String(localized: "Incomplete — skipped for now.", comment: "Preview why: transient folder."),
                    category: .review,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .skippedTransient
                ))
                continue
            }

            if SortRulesEvaluator.isExcluded(url: standardized, snapshot: snapshot) {
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: "—",
                    summary: String(localized: "Excluded — matches your ignore list.", comment: "Sort preview row."),
                    whyLine: String(localized: "On your ignore list.", comment: "Preview why: excluded."),
                    category: .misc,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .skippedExcluded
                ))
                continue
            }

            if fileURLMatchesGlobalSkipTags(standardized, snapshot: snapshot) {
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: "—",
                    summary: String(localized: "Skipped — protected Finder tag.", comment: "Sort preview row."),
                    whyLine: String(localized: "This folder has a tag on your “never sort” list.", comment: "Preview why: skip tag on folder."),
                    category: .misc,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .skippedProtectedTag
                ))
                continue
            }

            let (defaultRoot, _) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let destRoot = inboxRoot.appendingPathComponent(rel, isDirectory: true)

            let parent = standardized.deletingLastPathComponent().standardizedFileURL
            if parent == destRoot.standardizedFileURL {
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    proposedDestinationPath: standardized.path,
                    summary: String(localized: "Loose folder — already filed.", comment: "Sort preview loose folder."),
                    whyLine: String(localized: "Already in the Folders destination.", comment: "Preview why: loose folder in place."),
                    category: .folders,
                    matchedRuleName: nil,
                    addedTags: [],
                    planDisposition: .keptInPlace
                ))
                continue
            }

            try? fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let target = SortCollision.uniquify(destinationDirectory: destRoot, preferredFilename: standardized.lastPathComponent)
            let baseLabel = destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destRoot)
            let destLabel = baseLabel.isEmpty
                ? target.lastPathComponent
                : "\(baseLabel)/\(target.lastPathComponent)"
            out.append(SortPreviewEntry(
                id: UUID(),
                sourcePath: standardized.path,
                proposedDestinationPath: destLabel,
                summary: String.localizedStringWithFormat(
                    String(localized: "Loose folder → %@", comment: "Sort preview: relocate folder."),
                    destLabel
                ),
                whyLine: String(localized: "Moves the whole folder — nothing inside is sorted separately.", comment: "Preview why: opaque loose folder."),
                category: .folders,
                matchedRuleName: nil,
                addedTags: [],
                planDisposition: .wouldMove
            ))
        }
        return out
    }
}
