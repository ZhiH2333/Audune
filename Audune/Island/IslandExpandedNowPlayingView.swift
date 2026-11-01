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
                    TimelineView(.animation(minimumInterval: snapshot.isPlaying && isScrubbing == false ? 1.0 / 30.0 : nil)) { timeline in
                        playerBody(at: timeline.date)
                    }
                } else {
                    statusMessage(String(localized: "Nothing playing"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private func playerBody(at date: Date) -> some View {
        let duration = max(snapshot.durationSeconds, 0)
        let liveElapsed = snapshot.displayElapsed(at: date)
        let displayed = isScrubbing ? scrubValue : liveElapsed
        let progress = duration > 0 ? min(max(displayed / duration, 0), 1) : 0

        return HStack(alignment: .center, spacing: 12) {
            artworkView
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.title.isEmpty ? String(localized: "Unknown Title") : snapshot.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.96))
                            .lineLimit(1)
                        Text(snapshot.artist.isEmpty ? String(localized: "Unknown Artist") : snapshot.artist)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    sourceBadge
                }

                IslandNowPlayingScrubber(
                    progress: progress,
                    displayedSeconds: displayed,
                    durationSeconds: duration,
                    seekSupported: snapshot.seekSupported,
                    isScrubbing: $isScrubbing,
                    onScrubChanged: { fraction in
                        guard duration > 0 else { return }
                        scrubValue = fraction * duration
                    },
                    onScrubEnded: { fraction in
                        guard duration > 0, snapshot.seekSupported else { return }
                        let seconds = fraction * duration
                        scrubValue = seconds
                        onSeek(seconds)
                    }
                )

                transportRow
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var artworkView: some View {
        ZStack {
            if let artwork = snapshot.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 18)
                    .opacity(0.45)
                    .scaleEffect(1.15)
                    .frame(width: 68, height: 68)
                    .clipped()
            }

            Group {
                if let artwork = snapshot.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let icon = appIcon(for: snapshot.bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                }
                .accessibilityLabel(snapshot.bundleIdentifier)
        }
    }

    private var transportRow: some View {
        HStack(spacing: 18) {
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
                .font(.system(size: large ? 15 : 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: large ? 34 : 26, height: large ? 34 : 26)
                .background {
                    Circle()
                        .fill(Color.white.opacity(large ? 0.16 : 0.08))
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func statusMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
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

    private func appIcon(for bundleID: String) -> NSImage? {
        guard bundleID.isEmpty == false else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

private struct IslandNowPlayingScrubber: View {
    var progress: Double
    var displayedSeconds: Double
    var durationSeconds: Double
    var seekSupported: Bool
    @Binding var isScrubbing: Bool
    var onScrubChanged: (Double) -> Void
    var onScrubEnded: (Double) -> Void

    @State private var dragProgress: Double?

    var body: some View {
        let shown = dragProgress ?? progress
        VStack(spacing: 3) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fill = min(max(shown, 0), 1) * width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.72)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(fill, shown > 0 ? 4 : 0), height: 4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 11 : 8, height: isScrubbing ? 11 : 8)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: max(fill - (isScrubbing ? 5.5 : 4), 0))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(seekSupported ? dragGesture(width: width) : nil)
                .opacity(seekSupported ? 1 : 0.55)
            }
            .frame(height: 14)

            HStack {
                Text(formatTime(displayedSeconds))
                Spacer()
                Text(durationSeconds > 0 ? formatTime(durationSeconds) : "--:--")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.58))
        }
        .animation(.easeOut(duration: 0.12), value: isScrubbing)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = min(max(value.location.x / width, 0), 1)
                if isScrubbing == false {
                    isScrubbing = true
                }
                dragProgress = fraction
                onScrubChanged(fraction)
            }
            .onEnded { value in
                let fraction = min(max(value.location.x / width, 0), 1)
                dragProgress = nil
                isScrubbing = false
                onScrubEnded(fraction)
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
#endif
