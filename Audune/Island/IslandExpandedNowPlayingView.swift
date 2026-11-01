#if os(macOS)
import AppKit
import SwiftUI

struct IslandExpandedNowPlayingView: View {
    var snapshot: NowPlayingSnapshot
    var onTogglePlay: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onSeek: (Double) -> Void

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        Group {
            switch snapshot.availability {
            case .unavailable:
                statusMessage(String(localized: "Now Playing unavailable"))
            case .empty, .idle:
                statusMessage(String(localized: "Nothing playing"))
            case .listening:
                if snapshot.hasTrack {
                    playerBody
                } else {
                    statusMessage(String(localized: "Nothing playing"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var playerBody: some View {
        HStack(alignment: .center, spacing: 10) {
            artworkView
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.title.isEmpty ? String(localized: "Unknown Title") : snapshot.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(snapshot.artist.isEmpty ? String(localized: "Unknown Artist") : snapshot.artist)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    sourceBadge
                }
                progressRow
                transportRow
            }
        }
        .padding(.horizontal, 4)
    }

    private var artworkView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = snapshot.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let icon = appIcon(for: snapshot.bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .accessibilityLabel(snapshot.bundleIdentifier)
        }
    }

    private var progressRow: some View {
        let duration = max(snapshot.durationSeconds, 0)
        let displayed = isScrubbing ? scrubValue : snapshot.displayElapsed()
        return VStack(spacing: 2) {
            if duration > 0 {
                Slider(
                    value: Binding(
                        get: { displayed },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...duration,
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                            scrubValue = snapshot.displayElapsed()
                        } else {
                            isScrubbing = false
                            if snapshot.seekSupported {
                                onSeek(scrubValue)
                            }
                        }
                    }
                )
                .controlSize(.mini)
                .disabled(snapshot.seekSupported == false)
                .opacity(snapshot.seekSupported ? 1 : 0.55)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 3)
            }
            HStack {
                Text(formatTime(displayed))
                Spacer()
                Text(duration > 0 ? formatTime(duration) : "--:--")
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private var transportRow: some View {
        HStack(spacing: 14) {
            transportButton(symbol: "backward.fill", label: String(localized: "Previous Track"), action: onPrevious)
            transportButton(
                symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                label: snapshot.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                large: true,
                action: onTogglePlay
            )
            transportButton(symbol: "forward.fill", label: String(localized: "Next Track"), action: onNext)
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(symbol: String, label: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 14 : 11, weight: .semibold))
                .frame(width: large ? 28 : 22, height: large ? 28 : 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func statusMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }

    private var accessibilitySummary: String {
        switch snapshot.availability {
        case .unavailable:
            return String(localized: "Now Playing unavailable")
        case .empty, .idle:
            return String(localized: "Nothing playing")
        case .listening:
            return "\(snapshot.title), \(snapshot.artist)"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = abs(total % 60)
        return String(format: "%d:%02d", m, s)
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard bundleID.isEmpty == false else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
#endif
