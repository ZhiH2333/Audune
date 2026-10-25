import CoreGraphics
import Foundation

nonisolated enum IslandPresentationState: String, Equatable, Sendable {
    case disabled
    case compact
    case expanded
    case pinned

    var isExpandedOrPinned: Bool {
        self == .expanded || self == .pinned
    }

    var isVisible: Bool {
        self != .disabled
    }
}

nonisolated struct IslandStateContext: Equatable, Sendable {
    var state: IslandPresentationState = .compact
    var exitedAt: TimeInterval? = nil
    var pointerInside: Bool = false
    var pointerDown: Bool = false
}

nonisolated enum IslandEvent: Equatable, Sendable {
    case availabilityChanged(isEnabled: Bool, isSupported: Bool)
    case pointerEntered(hoverToExpand: Bool)
    case pointerExited(at: TimeInterval)
    case pointerDownChanged(Bool, at: TimeInterval)
    case collapseTimerFired(now: TimeInterval)
    case expandRequested
    case collapseRequested
    case togglePin(at: TimeInterval)
    case escapePressed
}

nonisolated enum IslandMotion {
    static let expandSeconds = 0.20
    static let collapseSeconds = 0.18
    static let defaultCollapseDelaySeconds = 0.35

    static func transitionSeconds(
        expanding: Bool,
        reduceMotion: Bool,
        followsReduceMotion: Bool = true
    ) -> Double {
        guard reduceMotion == false || followsReduceMotion == false else { return 0 }
        return expanding ? expandSeconds : collapseSeconds
    }
}

nonisolated enum IslandStateMachine {
    static let pointerSlop: CGFloat = 6

    static func pointerIsInside(
        windowFrame: CGRect,
        cursor: CGPoint,
        slop: CGFloat = pointerSlop
    ) -> Bool {
        guard windowFrame.width.isFinite, windowFrame.height.isFinite,
              windowFrame.width > 0, windowFrame.height > 0,
              cursor.x.isFinite, cursor.y.isFinite
        else {
            return false
        }
        let safeSlop = slop.isFinite && slop >= 0 ? slop : pointerSlop
        return windowFrame.insetBy(dx: -safeSlop, dy: -safeSlop).contains(cursor)
    }

    static func reduce(
        context: IslandStateContext,
        event: IslandEvent,
        collapseDelay: TimeInterval = IslandMotion.defaultCollapseDelaySeconds
    ) -> IslandStateContext {
        var next = context
        let delay = collapseDelay.isFinite ? max(collapseDelay, 0) : IslandMotion.defaultCollapseDelaySeconds

        switch event {
        case .availabilityChanged(let isEnabled, let isSupported):
            guard isEnabled, isSupported else {
                return IslandStateContext(
                    state: .disabled,
                    exitedAt: nil,
                    pointerInside: false,
                    pointerDown: false
                )
            }
            if next.state == .disabled {
                next.state = .compact
                next.exitedAt = nil
            }
            return next

        case .pointerEntered(let hoverToExpand):
            guard next.state != .disabled else { return next }
            next.pointerInside = true
            next.exitedAt = nil
            if next.state == .compact, hoverToExpand {
                next.state = .expanded
            }
            return next

        case .pointerExited(let timestamp):
            guard next.state != .disabled else { return next }
            next.pointerInside = false
            let safeTime = timestamp.isFinite ? timestamp : 0
            switch next.state {
            case .expanded:
                if next.pointerDown == false {
                    next.exitedAt = safeTime
                }
            case .pinned, .compact, .disabled:
                next.exitedAt = nil
            }
            return next

        case .pointerDownChanged(let down, let timestamp):
            guard next.state != .disabled else { return next }
            next.pointerDown = down
            let safeTime = timestamp.isFinite ? timestamp : 0
            if down {
                next.exitedAt = nil
            } else if next.pointerInside == false, next.state == .expanded {
                next.exitedAt = safeTime
            }
            return next

        case .collapseTimerFired(let now):
            guard next.state == .expanded,
                  next.pointerInside == false,
                  next.pointerDown == false,
                  let exitedAt = next.exitedAt
            else {
                return next
            }
            let safeNow = now.isFinite ? now : exitedAt
            if safeNow - exitedAt >= delay {
                next.state = .compact
                next.exitedAt = nil
            }
            return next

        case .expandRequested:
            guard next.state != .disabled else { return next }
            if next.state == .compact {
                next.state = .expanded
                next.exitedAt = nil
            }
            return next

        case .collapseRequested, .escapePressed:
            guard next.state != .disabled else { return next }
            next.state = .compact
            next.exitedAt = nil
            return next

        case .togglePin(let timestamp):
            let safeTime = timestamp.isFinite ? timestamp : 0
            switch next.state {
            case .disabled:
                return next
            case .compact, .expanded:
                next.state = .pinned
                next.exitedAt = nil
                return next
            case .pinned:
                next.state = .expanded
                next.exitedAt = next.pointerInside ? nil : safeTime
                return next
            }
        }
    }
}
