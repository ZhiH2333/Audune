import Foundation

nonisolated enum VisualPresetImportConflictPolicy: String, Equatable, CaseIterable {
    case importAsCopies
    case skipConflicts
}

nonisolated enum VisualPresetImportItemStatus: Equatable {
    case ready
    case renamed(from: String)
    case skippedConflict
}

nonisolated struct VisualPresetImportItem: Equatable {
    var entry: VisualPresetExchange.Entry
    var finalName: String?
    var status: VisualPresetImportItemStatus

    var willImport: Bool { finalName != nil }
}

nonisolated struct VisualPresetImportPlan: Equatable {
    var items: [VisualPresetImportItem]
    var policy: VisualPresetImportConflictPolicy

    var importCount: Int { items.filter(\.willImport).count }
    var skippedCount: Int { items.filter { $0.status == .skippedConflict }.count }

    var importCountByMode: [StudioVisualMode: Int] {
        var counts: [StudioVisualMode: Int] = [:]
        for item in items where item.willImport {
            counts[item.entry.mode, default: 0] += 1
        }
        return counts
    }
}

nonisolated enum VisualPresetImportPlanner {
    /// Builds an import plan against the current library. Does not write storage.
    static func plan(
        entries: [VisualPresetExchange.Entry],
        library: VisualPresetLibrary,
        policy: VisualPresetImportConflictPolicy
    ) -> Result<VisualPresetImportPlan, VisualPresetEditError> {
        guard library.canPersist else { return .failure(.unreadableStore) }
        guard entries.isEmpty == false else { return .failure(.notFound) }

        var items: [VisualPresetImportItem] = []
        var claimedNamesByMode: [StudioVisualMode: [String]] = [:]
        for mode in StudioVisualMode.allCases {
            claimedNamesByMode[mode] = (library.builtIns + library.customPresets)
                .filter { $0.mode == mode }
                .map(\.name)
        }

        for entry in entries {
            let mode = entry.mode
            let baseName = VisualPresetLibrary.normalizedName(entry.name)
            let reserved = claimedNamesByMode[mode] ?? []
            let conflicts = reserved.contains { VisualPresetExchange.sameName($0, baseName) }

            if conflicts == false {
                items.append(VisualPresetImportItem(entry: entry, finalName: baseName, status: .ready))
                claimedNamesByMode[mode, default: []].append(baseName)
                continue
            }

            switch policy {
            case .skipConflicts:
                items.append(VisualPresetImportItem(entry: entry, finalName: nil, status: .skippedConflict))
            case .importAsCopies:
                let renamed = uniqueCopyName(base: baseName, mode: mode, reserved: reserved)
                guard case .success(let name) = VisualPresetLibrary.validateImportName(renamed) else {
                    return .failure(.duplicateName)
                }
                items.append(VisualPresetImportItem(entry: entry, finalName: name, status: .renamed(from: baseName)))
                claimedNamesByMode[mode, default: []].append(name)
            }
        }

        let plan = VisualPresetImportPlan(items: items, policy: policy)
        if let capacityError = capacityError(for: plan, library: library) {
            return .failure(capacityError)
        }
        return .success(plan)
    }

    static func capacityError(for plan: VisualPresetImportPlan, library: VisualPresetLibrary) -> VisualPresetEditError? {
        for mode in StudioVisualMode.allCases {
            let existing = library.customPresets.filter { $0.mode == mode }.count
            let incoming = plan.importCountByMode[mode] ?? 0
            if existing + incoming > VisualPresetLibrary.maxCustomPresetsPerMode {
                return .limitReached
            }
        }
        return nil
    }

    private static func uniqueCopyName(base: String, mode: StudioVisualMode, reserved: [String]) -> String {
        func candidate(_ suffix: String) -> String {
            let room = max(0, VisualPresetLibrary.maximumNameLength - suffix.count)
            return String(base.prefix(room)) + suffix
        }
        func isFree(_ name: String) -> Bool {
            reserved.contains { VisualPresetExchange.sameName($0, name) } == false
        }

        let first = candidate(String(localized: " Copy"))
        if isFree(first) { return first }
        var index = 2
        while index < 100 {
            let next = candidate(String(localized: " Copy \(index)"))
            if isFree(next) { return next }
            index += 1
        }
        return first
    }
}

