import SwiftUI

/// Full-track progress with a tick at the point where the track gets scrobbled.
struct TrackProgressBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let marker: Double?          // 0...1, nil when the track can't be scrobbled
    let scrobbled: Bool

    @State private var hoveringMarker = false

    private var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.white).frame(width: w * fraction, height: 4)
                    if let marker {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(scrobbled ? Color.green : Color.white)
                            .frame(width: hoveringMarker ? 3 : 2, height: hoveringMarker ? 14 : 12)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                            .offset(x: w * marker - 1)
                        // Generous invisible hit area around the marker.
                        Color.clear
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .offset(x: w * marker - 11)
                            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hoveringMarker = h } }
                        if hoveringMarker {
                            tooltip(marker: marker)
                                .fixedSize()
                                .frame(width: w, alignment: .leading)
                                .offset(x: min(max(w * marker - 55, 0), w - 110), y: -22)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)

            HStack {
                Text(Self.format(position))
                Spacer()
                if marker == nil { Text("Too short to scrobble") }
                Spacer()
                Text(Self.format(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private func tooltip(marker: Double) -> some View {
        Group {
            if scrobbled {
                Label("Scrobbled", systemImage: "checkmark.circle.fill")
            } else {
                Text("Scrobbles at \(Self.format(marker * duration))")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(scrobbled ? Color.green : Color.white)
        .frame(width: 110)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.75), in: Capsule())
    }

    static func format(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "–:––" }
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
