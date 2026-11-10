import Foundation

nonisolated enum LyricsRoutingMode: String, Codable, Equatable, Sendable, CaseIterable {
    case autoFastestReliable
    case autoBestMatch
    case manual

    var displayName: String {
        switch self {
        case .autoFastestReliable: return "Auto · Fastest Reliable"
        case .autoBestMatch: return "Auto · Best Match"
        case .manual: return "Manual"
        }
    }
}

nonisolated struct LyricsRoutingSelection: Equatable, Sendable {
    var mode: LyricsRoutingMode
    var providerID: String?
    var nodeID: String?

    static let standard = LyricsRoutingSelection(
        mode: .autoBestMatch,
        providerID: nil,
        nodeID: nil
    )
}
