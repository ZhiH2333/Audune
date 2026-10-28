import Foundation

/// Portable JSON exchange for visual presets. Independent of `VisualPresetDocument` / UserDefaults.
nonisolated enum VisualPresetExchange {
    static let formatIdentifier = "audune.visualPresetExchange"
    static let supportedSchemaVersion = 1
    static let maximumFileSizeBytes = 512 * 1024
    static let maximumPresetsPerFile = VisualPresetLibrary.maxCustomPresetsPerMode * StudioVisualMode.allCases.count
    static let maximumNameLength = VisualPresetLibrary.maximumNameLength

    static func encode(_ presets: [VisualPreset], exportedAt: Date = Date()) -> Result<Data, VisualPresetExchangeError> {
        guard presets.isEmpty == false else { return .failure(.emptyPresets) }
        guard presets.count <= maximumPresetsPerFile else { return .failure(.tooManyPresets) }
        for preset in presets {
            guard preset.hasMatchingPayload() else { return .failure(.invalidPayload(preset.name)) }
        }
        let document = Document(
            format: formatIdentifier,
            schemaVersion: supportedSchemaVersion,
            exportedAt: ISO8601DateFormatter().string(from: exportedAt),
            presets: presets.map(Entry.init(snapshotting:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return .failure(.encodeFailed) }
        guard data.count <= maximumFileSizeBytes else { return .failure(.fileTooLarge) }
        return .success(data)
    }

    /// Parses and strictly validates exchange JSON. Never writes UserDefaults.
    static func decode(_ data: Data) -> Result<[Entry], VisualPresetExchangeError> {
        guard data.count <= maximumFileSizeBytes else { return .failure(.fileTooLarge) }
        guard data.isEmpty == false else { return .failure(.invalidJSON) }

        let object: [String: Any]
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dict = json as? [String: Any] else { return .failure(.invalidJSON) }
            object = dict
        } catch {
            return .failure(.invalidJSON)
        }

        guard let format = object["format"] as? String else { return .failure(.missingFormat) }
        guard format == formatIdentifier else { return .failure(.unsupportedFormat(format)) }

        guard let schemaVersion = object["schemaVersion"] as? Int else { return .failure(.missingSchemaVersion) }
        guard schemaVersion == supportedSchemaVersion else {
            return .failure(.unsupportedSchemaVersion(schemaVersion))
        }

        guard let rawPresets = object["presets"] as? [Any] else { return .failure(.missingPresets) }
        guard rawPresets.isEmpty == false else { return .failure(.emptyPresets) }
        guard rawPresets.count <= maximumPresetsPerFile else { return .failure(.tooManyPresets) }

        var entries: [Entry] = []
        entries.reserveCapacity(rawPresets.count)
        for (index, raw) in rawPresets.enumerated() {
            guard let presetObject = raw as? [String: Any] else {
                return .failure(.invalidPreset(index: index, reason: "Preset \(index + 1) is not an object."))
            }
            switch Entry.parse(presetObject, index: index) {
            case .success(let entry):
                entries.append(entry)
            case .failure(let error):
                return .failure(error)
            }
        }

        if let conflict = duplicateNameConflict(in: entries) {
            return .failure(conflict)
        }
        return .success(entries)
    }
}

nonisolated struct VisualPresetExchangeDocument: Codable, Equatable {
    var format: String
    var schemaVersion: Int
    var exportedAt: String?
    var presets: [VisualPresetExchange.Entry]
}

extension VisualPresetExchange {
    typealias Document = VisualPresetExchangeDocument

    nonisolated struct Entry: Codable, Equatable {
        var name: String
        var mode: StudioVisualMode
        var spectrum: SpectrumPreferences?
        var waveform: WaveformPreferences?
        var orbit: OrbitPreferences?

        init(name: String, mode: StudioVisualMode, spectrum: SpectrumPreferences? = nil, waveform: WaveformPreferences? = nil, orbit: OrbitPreferences? = nil) {
            self.name = name
            self.mode = mode
            self.spectrum = spectrum
            self.waveform = waveform
            self.orbit = orbit
        }

        init(snapshotting preset: VisualPreset) {
            let clamped = preset.clamped()
            self.name = VisualPresetLibrary.normalizedName(clamped.name)
            self.mode = clamped.mode
            self.spectrum = clamped.spectrum
            self.waveform = clamped.waveform
            self.orbit = clamped.orbit
        }

        func asCustomPreset(id: String) -> VisualPreset {
            VisualPreset(
                id: id,
                name: name,
                mode: mode,
                kind: .custom,
                spectrum: spectrum,
                waveform: waveform,
                orbit: orbit
            ).clamped()
        }

        private enum CodingKeys: String, CodingKey {
            case name, mode, spectrum, waveform, orbit
        }

        /// Strict parse from a JSON object dictionary. Requires all mode fields; rejects out-of-range values.
        static func parse(_ object: [String: Any], index: Int) -> Result<Entry, VisualPresetExchangeError> {
            let label = "Preset \(index + 1)"
            guard let rawName = object["name"] as? String else {
                return .failure(.invalidPreset(index: index, reason: "\(label) is missing a name."))
            }
            let name = VisualPresetLibrary.normalizedName(rawName)
            guard name.isEmpty == false else {
                return .failure(.invalidPreset(index: index, reason: "\(label) has an empty name."))
            }
            guard name.count <= VisualPresetExchange.maximumNameLength else {
                return .failure(.invalidPreset(index: index, reason: "\(label) name is longer than \(VisualPresetExchange.maximumNameLength) characters."))
            }

            guard let modeRaw = object["mode"] as? String else {
                return .failure(.invalidPreset(index: index, reason: "\(label) is missing a mode."))
            }
            guard let mode = StudioVisualMode(rawValue: modeRaw) else {
                return .failure(.invalidPreset(index: index, reason: "\(label) has an unsupported mode."))
            }

            let hasSpectrum = object["spectrum"] != nil && !(object["spectrum"] is NSNull)
            let hasWaveform = object["waveform"] != nil && !(object["waveform"] is NSNull)
            let hasOrbit = object["orbit"] != nil && !(object["orbit"] is NSNull)
            let payloadCount = [hasSpectrum, hasWaveform, hasOrbit].filter(\.self).count
            guard payloadCount == 1 else {
                return .failure(.invalidPreset(index: index, reason: "\(label) must include exactly one mode configuration."))
            }

            switch mode {
            case .spectrum:
                guard hasSpectrum, let payload = object["spectrum"] as? [String: Any] else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) is missing spectrum settings."))
                }
                guard hasWaveform == false, hasOrbit == false else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) has extra mode configurations."))
                }
                switch StrictSpectrum.decode(payload, label: label, index: index) {
                case .success(let spectrum):
                    return .success(Entry(name: name, mode: .spectrum, spectrum: spectrum))
                case .failure(let error):
                    return .failure(error)
                }
            case .waveform:
                guard hasWaveform, let payload = object["waveform"] as? [String: Any] else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) is missing waveform settings."))
                }
                guard hasSpectrum == false, hasOrbit == false else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) has extra mode configurations."))
                }
                switch StrictWaveform.decode(payload, label: label, index: index) {
                case .success(let waveform):
                    return .success(Entry(name: name, mode: .waveform, waveform: waveform))
                case .failure(let error):
                    return .failure(error)
                }
            case .orbit:
                guard hasOrbit, let payload = object["orbit"] as? [String: Any] else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) is missing orbit settings."))
                }
                guard hasSpectrum == false, hasWaveform == false else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) has extra mode configurations."))
                }
                switch StrictOrbit.decode(payload, label: label, index: index) {
                case .success(let orbit):
                    return .success(Entry(name: name, mode: .orbit, orbit: orbit))
                case .failure(let error):
                    return .failure(error)
                }
            }
        }
    }

    private static func duplicateNameConflict(in entries: [Entry]) -> VisualPresetExchangeError? {
        for mode in StudioVisualMode.allCases {
            let named = entries.filter { $0.mode == mode }
            for (index, entry) in named.enumerated() {
                let later = named.dropFirst(index + 1)
                if later.contains(where: { sameName($0.name, entry.name) }) {
                    return .duplicateNameInFile(entry.name)
                }
            }
        }
        return nil
    }

    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
    }
}

nonisolated enum VisualPresetExchangeError: Error, Equatable {
    case fileTooLarge
    case invalidJSON
    case missingFormat
    case unsupportedFormat(String)
    case missingSchemaVersion
    case unsupportedSchemaVersion(Int)
    case missingPresets
    case emptyPresets
    case tooManyPresets
    case encodeFailed
    case invalidPayload(String)
    case duplicateNameInFile(String)
    case invalidPreset(index: Int, reason: String)

    var message: String {
        switch self {
        case .fileTooLarge:
            return String(localized: "That preset file is too large.")
        case .invalidJSON:
            return String(localized: "That file is not valid JSON.")
        case .missingFormat, .unsupportedFormat:
            return String(localized: "That file is not an Audune preset exchange file.")
        case .missingSchemaVersion:
            return String(localized: "That preset file is missing a schema version.")
        case .unsupportedSchemaVersion:
            return String(localized: "That preset file uses an unsupported schema version.")
        case .missingPresets, .emptyPresets:
            return String(localized: "That preset file does not contain any presets.")
        case .tooManyPresets:
            return String(localized: "That preset file contains too many presets.")
        case .encodeFailed:
            return String(localized: "The presets could not be exported.")
        case .invalidPayload:
            return String(localized: "A selected preset is missing its visual settings.")
        case .duplicateNameInFile(let name):
            return String(localized: "That preset file lists \"\(name)\" more than once for the same mode.")
        case .invalidPreset(_, let reason):
            return reason
        }
    }
}

// MARK: - Strict payload decoding

private enum StrictSpectrum {
    static let requiredKeys: Set<String> = [
        "barCount", "scale", "minHz", "maxHz", "barGap", "cornerRadius", "stroke", "colorMode",
        "sensitivity", "amplitude", "smoothing", "attackMs", "releaseMs", "peakHold", "peakHoldSeconds",
        "peakFallPerSecond", "silenceGateEnabled", "silenceThreshold"
    ]

    static func decode(_ object: [String: Any], label: String, index: Int) -> Result<SpectrumPreferences, VisualPresetExchangeError> {
        for key in requiredKeys where object[key] == nil || object[key] is NSNull {
            return .failure(.invalidPreset(index: index, reason: "\(label) is missing spectrum.\(key)."))
        }
        do {
            let barCount = try requireInt(object, "barCount", label: label, index: index)
            let scaleRaw = try requireString(object, "scale", label: label, index: index)
            guard let scale = SpectrumScale(rawValue: scaleRaw) else {
                return .failure(.invalidPreset(index: index, reason: "\(label) has an unsupported spectrum.scale."))
            }
            let colorModeRaw = try requireString(object, "colorMode", label: label, index: index)
            guard let colorMode = SpectrumColorMode(rawValue: colorModeRaw) else {
                return .failure(.invalidPreset(index: index, reason: "\(label) has an unsupported spectrum.colorMode."))
            }
            let prefs = SpectrumPreferences(
                barCount: barCount,
                scale: scale,
                minHz: try requireFiniteDouble(object, "minHz", label: label, index: index),
                maxHz: try requireFiniteDouble(object, "maxHz", label: label, index: index),
                barGap: try requireFiniteDouble(object, "barGap", label: label, index: index),
                cornerRadius: try requireFiniteDouble(object, "cornerRadius", label: label, index: index),
                stroke: try requireBool(object, "stroke", label: label, index: index),
                colorMode: colorMode,
                sensitivity: try requireFiniteDouble(object, "sensitivity", label: label, index: index),
                amplitude: try requireFiniteDouble(object, "amplitude", label: label, index: index),
                smoothing: try requireFiniteDouble(object, "smoothing", label: label, index: index),
                attackMs: try requireFiniteDouble(object, "attackMs", label: label, index: index),
                releaseMs: try requireFiniteDouble(object, "releaseMs", label: label, index: index),
                peakHold: try requireBool(object, "peakHold", label: label, index: index),
                peakHoldSeconds: try requireFiniteDouble(object, "peakHoldSeconds", label: label, index: index),
                peakFallPerSecond: try requireFiniteDouble(object, "peakFallPerSecond", label: label, index: index),
                silenceGateEnabled: try requireBool(object, "silenceGateEnabled", label: label, index: index),
                silenceThreshold: try requireFiniteDouble(object, "silenceThreshold", label: label, index: index)
            )
            let clamped = prefs.clamped()
            if prefs != clamped {
                return .failure(.invalidPreset(index: index, reason: "\(label) has spectrum values outside the allowed range."))
            }
            return .success(clamped)
        } catch let error as VisualPresetExchangeError {
            return .failure(error)
        } catch {
            return .failure(.invalidPreset(index: index, reason: "\(label) has invalid spectrum settings."))
        }
    }
}

private enum StrictWaveform {
    static let requiredKeys: Set<String> = [
        "lineWidth", "amplitude", "verticalRange", "smoothing", "density", "style", "fillStrength"
    ]

    static func decode(_ object: [String: Any], label: String, index: Int) -> Result<WaveformPreferences, VisualPresetExchangeError> {
        for key in requiredKeys where object[key] == nil || object[key] is NSNull {
            return .failure(.invalidPreset(index: index, reason: "\(label) is missing waveform.\(key)."))
        }
        do {
            let styleRaw = try requireString(object, "style", label: label, index: index)
            // Reject unknown styles; do not use WaveformStyle's legacy fallback to `.line`.
            let style: WaveformStyle
            switch styleRaw {
            case "line": style = .line
            case "softFill": style = .softFill
            case "mirror": style = .mirror
            default:
                return .failure(.invalidPreset(index: index, reason: "\(label) has an unsupported waveform.style."))
            }
            var customColor: StudioColor?
            if object["customColor"] != nil && !(object["customColor"] is NSNull) {
                let hex = try requireString(object, "customColor", label: label, index: index)
                guard let color = StudioColor(hex: hex) else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) has an invalid waveform.customColor."))
                }
                customColor = color
            }
            let prefs = WaveformPreferences(
                lineWidth: try requireFiniteDouble(object, "lineWidth", label: label, index: index),
                amplitude: try requireFiniteDouble(object, "amplitude", label: label, index: index),
                verticalRange: try requireFiniteDouble(object, "verticalRange", label: label, index: index),
                smoothing: try requireFiniteDouble(object, "smoothing", label: label, index: index),
                density: try requireInt(object, "density", label: label, index: index),
                style: style,
                fillStrength: try requireFiniteDouble(object, "fillStrength", label: label, index: index),
                customColor: customColor
            )
            let clamped = prefs.clamped()
            if prefs != clamped {
                return .failure(.invalidPreset(index: index, reason: "\(label) has waveform values outside the allowed range."))
            }
            return .success(clamped)
        } catch let error as VisualPresetExchangeError {
            return .failure(error)
        } catch {
            return .failure(.invalidPreset(index: index, reason: "\(label) has invalid waveform settings."))
        }
    }
}

private enum StrictOrbit {
    static let requiredKeys: Set<String> = [
        "barCount", "inner", "outerScale", "gapDegrees", "mirrored", "stroke", "lineWidth",
        "amplitude", "smoothing", "layerMode", "pulseStrength"
    ]

    static func decode(_ object: [String: Any], label: String, index: Int) -> Result<OrbitPreferences, VisualPresetExchangeError> {
        for key in requiredKeys where object[key] == nil || object[key] is NSNull {
            return .failure(.invalidPreset(index: index, reason: "\(label) is missing orbit.\(key)."))
        }
        do {
            let layerRaw = try requireString(object, "layerMode", label: label, index: index)
            guard let layerMode = OrbitLayerMode(rawValue: layerRaw) else {
                return .failure(.invalidPreset(index: index, reason: "\(label) has an unsupported orbit.layerMode."))
            }
            var customColor: StudioColor?
            if object["customColor"] != nil && !(object["customColor"] is NSNull) {
                let hex = try requireString(object, "customColor", label: label, index: index)
                guard let color = StudioColor(hex: hex) else {
                    return .failure(.invalidPreset(index: index, reason: "\(label) has an invalid orbit.customColor."))
                }
                customColor = color
            }
            let prefs = OrbitPreferences(
                barCount: try requireInt(object, "barCount", label: label, index: index),
                inner: try requireFiniteDouble(object, "inner", label: label, index: index),
                outerScale: try requireFiniteDouble(object, "outerScale", label: label, index: index),
                gapDegrees: try requireFiniteDouble(object, "gapDegrees", label: label, index: index),
                mirrored: try requireBool(object, "mirrored", label: label, index: index),
                stroke: try requireBool(object, "stroke", label: label, index: index),
                lineWidth: try requireFiniteDouble(object, "lineWidth", label: label, index: index),
                amplitude: try requireFiniteDouble(object, "amplitude", label: label, index: index),
                smoothing: try requireFiniteDouble(object, "smoothing", label: label, index: index),
                layerMode: layerMode,
                pulseStrength: try requireFiniteDouble(object, "pulseStrength", label: label, index: index),
                customColor: customColor
            )
            let clamped = prefs.clamped()
            if prefs != clamped {
                return .failure(.invalidPreset(index: index, reason: "\(label) has orbit values outside the allowed range."))
            }
            return .success(clamped)
        } catch let error as VisualPresetExchangeError {
            return .failure(error)
        } catch {
            return .failure(.invalidPreset(index: index, reason: "\(label) has invalid orbit settings."))
        }
    }
}

private func requireInt(_ object: [String: Any], _ key: String, label: String, index: Int) throws -> Int {
    if let value = object[key] as? Int { return value }
    if let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite, doubleValue.rounded() == doubleValue else {
            throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has a non-integer \(key).")
        }
        return number.intValue
    }
    throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has an invalid \(key).")
}

private func requireFiniteDouble(_ object: [String: Any], _ key: String, label: String, index: Int) throws -> Double {
    if let value = object[key] as? Double {
        guard value.isFinite else {
            throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has a non-finite \(key).")
        }
        return value
    }
    if let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        let value = number.doubleValue
        guard value.isFinite else {
            throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has a non-finite \(key).")
        }
        return value
    }
    throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has an invalid \(key).")
}

private func requireBool(_ object: [String: Any], _ key: String, label: String, index: Int) throws -> Bool {
    if let value = object[key] as? Bool { return value }
    throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has an invalid \(key).")
}

private func requireString(_ object: [String: Any], _ key: String, label: String, index: Int) throws -> String {
    if let value = object[key] as? String { return value }
    throw VisualPresetExchangeError.invalidPreset(index: index, reason: "\(label) has an invalid \(key).")
}
