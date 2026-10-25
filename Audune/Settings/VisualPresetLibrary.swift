import Foundation

/// Custom visual presets stored as one versioned JSON blob. A failed read never writes the key back.
nonisolated struct VisualPresetLibrary {
    static let maximumNameLength = 40
    static let maxCustomPresetsPerMode = 24

    private(set) var customPresets: [VisualPreset]
    private(set) var appliedIDByMode: [String: String]
    private(set) var canPersist: Bool
    let builtIns: [VisualPreset]
    var encodeDocument: (VisualPresetDocument) -> Result<Data, VisualPresetEditError>

    static func load(from defaults: UserDefaults = .standard, builtIns: [VisualPreset] = []) -> VisualPresetLibrary {
        var library = VisualPresetLibrary(
            customPresets: [],
            appliedIDByMode: [:],
            canPersist: true,
            builtIns: builtIns,
            encodeDocument: Self.defaultEncode
        )
        guard let data = defaults.data(forKey: StudioPreferenceKey.visualPresets) else {
            return library
        }
        guard let document = try? JSONDecoder().decode(VisualPresetDocument.self, from: data),
              Self.isReadable(document) else {
            library.canPersist = false
            return library
        }
        library.customPresets = document.customPresets.map { $0.clamped() }
        library.appliedIDByMode = document.appliedIDByMode
        return library
    }

    func appliedID(for mode: StudioVisualMode) -> String? {
        appliedIDByMode[mode.rawValue]
    }

    func presets(for mode: StudioVisualMode) -> [VisualPreset] {
        builtIns.filter { $0.mode == mode } + customPresets.filter { $0.mode == mode }
    }

    @discardableResult
    func save(to defaults: UserDefaults) -> Bool {
        guard canPersist else { return false }
        let document = VisualPresetDocument(
            schemaVersion: VisualPresetDocument.supportedSchemaVersion,
            customPresets: customPresets,
            appliedIDByMode: appliedIDByMode
        )
        guard case .success(let data) = encodeDocument(document) else { return false }
        defaults.set(data, forKey: StudioPreferenceKey.visualPresets)
        return true
    }

    @discardableResult
    mutating func resetLibrary(in defaults: UserDefaults) -> Bool {
        let previousCustom = customPresets
        let previousApplied = appliedIDByMode
        let previousPersist = canPersist
        customPresets = []
        appliedIDByMode = [:]
        canPersist = true
        guard save(to: defaults) else {
            customPresets = previousCustom
            appliedIDByMode = previousApplied
            canPersist = previousPersist
            return false
        }
        return true
    }

    mutating func addCustom(
        name: String,
        mode: StudioVisualMode,
        spectrum: SpectrumPreferences? = nil,
        waveform: WaveformPreferences? = nil,
        orbit: OrbitPreferences? = nil,
        to defaults: UserDefaults
    ) -> Result<VisualPreset, VisualPresetEditError> {
        guard canPersist else { return .failure(.unreadableStore) }
        let trimmed: String
        switch validatedName(name, mode: mode, ignoringID: nil) {
        case .success(let name):
            trimmed = name
        case .failure(let error):
            return .failure(error)
        }
        guard customPresets.filter({ $0.mode == mode }).count < Self.maxCustomPresetsPerMode else {
            return .failure(.limitReached)
        }
        guard let id = makeID() else { return .failure(.duplicateID) }
        let preset = VisualPreset(
            id: id,
            name: trimmed,
            mode: mode,
            kind: .custom,
            spectrum: spectrum?.clamped(),
            waveform: waveform?.clamped(),
            orbit: orbit?.clamped()
        ).clamped()
        guard preset.hasMatchingPayload() else { return .failure(.modeMismatch) }
        customPresets.append(preset)
        guard save(to: defaults) else {
            customPresets.removeLast()
            return .failure(.persistFailed)
        }
        return .success(preset)
    }

    mutating func rename(id: String, to name: String, in defaults: UserDefaults) -> Result<Void, VisualPresetEditError> {
        guard canPersist else { return .failure(.unreadableStore) }
        if builtIns.contains(where: { $0.id == id }) { return .failure(.builtInLocked) }
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        if customPresets[index].kind != .custom { return .failure(.builtInLocked) }
        let trimmed: String
        switch validatedName(name, mode: customPresets[index].mode, ignoringID: id) {
        case .success(let name):
            trimmed = name
        case .failure(let error):
            return .failure(error)
        }
        let previous = customPresets[index].name
        customPresets[index].name = trimmed
        guard save(to: defaults) else {
            customPresets[index].name = previous
            return .failure(.persistFailed)
        }
        return .success(())
    }

    mutating func delete(id: String, in defaults: UserDefaults) -> Result<Void, VisualPresetEditError> {
        guard canPersist else { return .failure(.unreadableStore) }
        if builtIns.contains(where: { $0.id == id }) { return .failure(.builtInLocked) }
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        if customPresets[index].kind != .custom { return .failure(.builtInLocked) }
        let removed = customPresets.remove(at: index)
        let previousApplied = appliedIDByMode
        for (mode, applied) in appliedIDByMode where applied == removed.id {
            appliedIDByMode.removeValue(forKey: mode)
        }
        guard save(to: defaults) else {
            customPresets.insert(removed, at: index)
            appliedIDByMode = previousApplied
            return .failure(.persistFailed)
        }
        return .success(())
    }

    mutating func setAppliedID(_ id: String?, for mode: StudioVisualMode, in defaults: UserDefaults) -> Result<Void, VisualPresetEditError> {
        guard canPersist else { return .failure(.unreadableStore) }
        let key = mode.rawValue
        let previous = appliedIDByMode[key]
        if let id {
            appliedIDByMode[key] = id
        } else {
            appliedIDByMode.removeValue(forKey: key)
        }
        guard save(to: defaults) else {
            if let previous {
                appliedIDByMode[key] = previous
            } else {
                appliedIDByMode.removeValue(forKey: key)
            }
            return .failure(.persistFailed)
        }
        return .success(())
    }

    func validatedName(_ raw: String, mode: StudioVisualMode, ignoringID: String?) -> Result<String, VisualPresetEditError> {
        let name = Self.normalizedName(raw)
        guard name.isEmpty == false else { return .failure(.emptyName) }
        guard name.count <= Self.maximumNameLength else { return .failure(.nameTooLong) }
        let reserved = builtIns + customPresets
        let conflict = reserved.contains { preset in
            preset.mode == mode && preset.id != ignoringID && Self.sameName(preset.name, name)
        }
        guard conflict == false else { return .failure(.duplicateName) }
        return .success(name)
    }

    static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
    }

    private func makeID() -> String? {
        for _ in 0..<8 {
            let id = UUID().uuidString
            let taken = customPresets.contains { $0.id == id } || builtIns.contains { $0.id == id }
            if taken == false { return id }
        }
        return nil
    }

    private static func isReadable(_ document: VisualPresetDocument) -> Bool {
        guard document.schemaVersion == VisualPresetDocument.supportedSchemaVersion else { return false }
        let presets = document.customPresets
        let ids = presets.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ $0.isEmpty == false }) else { return false }
        guard presets.allSatisfy({ preset in
            preset.kind == .custom
                && preset.hasMatchingPayload()
                && preset.name == normalizedName(preset.name)
                && preset.name.isEmpty == false
                && preset.name.count <= maximumNameLength
        }) else { return false }
        for mode in StudioVisualMode.allCases {
            let named = presets.filter { $0.mode == mode }
            guard named.count <= maxCustomPresetsPerMode else { return false }
            for (index, preset) in named.enumerated() {
                let later = named.dropFirst(index + 1)
                if later.contains(where: { sameName($0.name, preset.name) }) { return false }
            }
        }
        return true
    }

    private static func defaultEncode(_ document: VisualPresetDocument) -> Result<Data, VisualPresetEditError> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return .failure(.persistFailed) }
        return .success(data)
    }
}
