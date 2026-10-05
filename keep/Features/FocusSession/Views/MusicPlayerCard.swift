import SwiftUI

struct MusicPlayerCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Image("CozyCorner")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("THE LISTENING CORNER", systemImage: "waveform")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(KeepTheme.paper.opacity(0.95), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Slow afternoons")
                                    .font(.system(size: 23, design: .serif))
                                Text("Lofi & ambient · coming soon")
                                    .font(.system(size: 12))
                                    .foregroundStyle(KeepTheme.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "music.note")
                                .font(.system(size: 20, weight: .light))
                                .accessibilityHidden(true)
                        }
                        HStack(spacing: 18) {
                            musicControl("backward.end.fill", label: "Previous track")
                            Button {} label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(KeepTheme.paper)
                                    .frame(width: 42, height: 42)
                                    .background(KeepTheme.ink, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                            .accessibilityLabel("Play music, coming soon")
                            musicControl("forward.end.fill", label: "Next track")
                            Spacer()
                            musicControl("speaker.wave.2", label: "Music volume")
                        }
                        .help("Music playback will be available later")
                    }
                    .padding(16)
                    .background {
                        if reduceTransparency {
                            RoundedRectangle(cornerRadius: 17).fill(KeepTheme.paper)
                        } else {
                            RoundedRectangle(cornerRadius: 17).fill(.regularMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17)
                                        .fill(KeepTheme.paper.opacity(0.58))
                                }
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(KeepTheme.paper.opacity(0.7), lineWidth: 1)
                    }
                }
                .padding(16)
            }
            .foregroundStyle(KeepTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 288, maxHeight: .infinity)
    }

    private func musicControl(_ symbol: String, label: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("\(label), coming soon")
    }
}

#Preview {
    MusicPlayerCard().padding().frame(width: 450)
}
