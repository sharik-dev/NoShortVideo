//
//  MusicPlayerView.swift
//  No short video
//

import SwiftUI

/// Lecteur plein écran des MP3 téléchargés, calqué sur Spotify : pochette,
/// titre, barre de lecture qu'on fait glisser, commandes (aléatoire,
/// précédent, lecture, suivant, répétition), jauge de volume et « À suivre ».
///
/// Le fond prend la couleur dominante de la pochette, comme sur Spotify : deux
/// morceaux ne se ressemblent pas, et on sait d'un coup d'œil lequel joue.
struct MusicPlayerView: View {

    @ObservedObject private var player = OfflineMusicPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var lang: String = "en"

    /// Position pendant qu'on fait glisser la barre : le temps affiché suit le
    /// doigt, le son ne saute qu'au lâcher.
    @State private var scrubTime: Double?
    @State private var dominant: Color = Color(white: 0.2)
    @State private var dragDown: CGFloat = 0

    private let accent = Color(red: 0.12, green: 0.84, blue: 0.38)
    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 8)
                    artwork
                        .padding(.top, 28)
                    titleRow
                        .padding(.top, 30)
                    scrubber
                        .padding(.top, 22)
                    controls
                        .padding(.top, 14)
                    volumeRow
                        .padding(.top, 26)
                    upNext
                        .padding(.top, 34)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .offset(y: dragDown)
        // Glisser vers le bas referme, comme la feuille de Spotify.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in if v.translation.height > 0 { dragDown = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 140 { dismiss() }
                    withAnimation(.spring(response: 0.3)) { dragDown = 0 }
                }
        )
        .preferredColorScheme(.dark)
        .onAppear { refreshColor() }
        .onChange(of: player.current?.id) { refreshColor() }
        .onChange(of: player.queue.isEmpty) { if player.queue.isEmpty { dismiss() } }
    }

    // MARK: - Fond

    private var background: some View {
        LinearGradient(
            colors: [dominant, dominant.opacity(0.55), Color(white: 0.07), Color(white: 0.07)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: dominant)
    }

    private func refreshColor() {
        guard let image = player.current?.artwork, let color = image.averageColor else {
            dominant = Color(white: 0.2); return
        }
        dominant = Color(color)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(t("LECTURE EN COURS", "NOW PLAYING"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(t("Ma musique", "My Music"))
                    .font(.system(size: 13, weight: .bold))
            }
            Spacer()
            Button {
                player.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Pochette

    private var artwork: some View {
        GeometryReader { geo in
            Group {
                if let image = player.current?.artwork {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color(white: 0.18)
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            // La pochette se tasse un peu en pause, comme sur Spotify.
            .scaleEffect(player.isPlaying ? 1 : 0.88)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Titre

    private var titleRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(t("Hors ligne · MP3", "Offline · MP3"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 12)
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(accent)
        }
    }

    // MARK: - Barre de lecture

    private var scrubber: some View {
        let shown = scrubTime ?? player.currentTime
        let total = max(player.duration, 0.01)
        let active = scrubTime != nil

        return VStack(spacing: 6) {
            GeometryReader { geo in
                let fraction = CGFloat(min(max(shown / total, 0), 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(active ? accent : .white)
                        .frame(width: geo.size.width * fraction)
                    Circle()
                        .fill(.white)
                        .frame(width: active ? 16 : 12, height: active ? 16 : 12)
                        .offset(x: geo.size.width * fraction - (active ? 8 : 6))
                }
                .frame(height: active ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let f = min(max(v.location.x / geo.size.width, 0), 1)
                            scrubTime = Double(f) * total
                        }
                        .onEnded { _ in
                            if let scrubTime { player.seek(to: scrubTime) }
                            scrubTime = nil
                        }
                )
                .animation(.easeOut(duration: 0.15), value: active)
            }
            .frame(height: 20)

            HStack {
                Text(SavedVideo.formatTime(shown))
                Spacer()
                Text("-" + SavedVideo.formatTime(max(0, player.duration - shown)))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Commandes

    private var controls: some View {
        HStack {
            Button { player.toggleShuffle() } label: {
                toggleIcon("shuffle", on: player.shuffle)
            }
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 30))
            }
            Spacer()
            Button { player.togglePlay() } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 70, height: 70)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.black)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 30))
            }
            Spacer()
            Button { player.cycleRepeat() } label: {
                toggleIcon(player.repeatMode == .one ? "repeat.1" : "repeat",
                           on: player.repeatMode != .off)
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
    }

    /// Icône verte avec un point dessous quand l'option est active — le code
    /// visuel de Spotify pour l'aléatoire et la répétition.
    private func toggleIcon(_ name: String, on: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: name)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(on ? accent : .white.opacity(0.8))
            Circle()
                .fill(on ? accent : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Volume

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Button { player.volume = 0 } label: {
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 14))
                    .frame(width: 22)
            }
            Slider(
                value: Binding(get: { Double(player.volume) },
                               set: { player.volume = Float($0) }),
                in: 0...1
            )
            .tint(.white)
            Button { player.volume = 1 } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .frame(width: 22)
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .buttonStyle(.plain)
    }

    // MARK: - À suivre

    @ViewBuilder
    private var upNext: some View {
        let tracks = player.upNext
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("À suivre", "Up next"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                ForEach(Array(tracks.prefix(20).enumerated()), id: \.element.id) { _, track in
                    Button {
                        player.jump(to: track)
                    } label: {
                        HStack(spacing: 12) {
                            MusicArtwork(track: track)
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(track.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(track.formattedDuration)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        }
    }
}

// MARK: - Mini-barre

/// La barre posée en bas pendant qu'un MP3 joue, comme la mini-barre de
/// Spotify : pochette, titre, lecture / suivant, et un filet de progression.
/// Un appui ouvre le lecteur plein écran ; le chevron à droite la réduit en
/// bulle flottante (`MusicMiniBubble`). Même verre que la barre d'outils.
struct MusicMiniBar: View {

    @ObservedObject private var player = OfflineMusicPlayer.shared
    var onOpen: () -> Void
    /// Absent (bibliothèque), pas de bouton masquer.
    var onHide: (() -> Void)? = nil

    @AppStorage("appLanguage") private var lang: String = "en"

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    MusicArtwork(track: track)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.trailing, 4)
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    MusicGlass.iconButton(player.isPlaying ? "pause.fill" : "play.fill", size: 18,
                                          label: player.isPlaying ? t("Pause", "Pause") : t("Lecture", "Play")) {
                        player.togglePlay()
                    }
                    MusicGlass.iconButton("forward.end.fill", size: 15,
                                          label: t("Suivant", "Next")) {
                        player.next()
                    }
                    if let onHide {
                        MusicGlass.hideButton(label: t("Masquer le lecteur", "Hide the player"), action: onHide)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 7)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(MusicGlass.accent)
                            .frame(width: geo.size.width * progress)
                            .shadow(color: MusicGlass.accent.opacity(0.7), radius: 3)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 5)
            }
            .musicGlass(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture(perform: onOpen)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(player.currentTime / player.duration, 1))
    }
}

/// La mini-barre masquée : la pochette dans une bulle, cerclée de la
/// progression du morceau.
struct MusicMiniBubble: View {

    @ObservedObject private var player = OfflineMusicPlayer.shared

    var body: some View {
        if let track = player.current {
            MusicBubble(
                isPlaying: player.isPlaying,
                progress: player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
            ) {
                MusicArtwork(track: track)
            }
        }
    }
}

/// Pochette d'un morceau : la miniature locale, sinon une note.
struct MusicArtwork: View {
    let track: SavedVideo

    var body: some View {
        if let image = track.artwork {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.22)
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Pochette sans bandes noires

extension SavedVideo {
    /// La miniature YouTube (`hqdefault`) est en 4:3 : l'image 16:9 y est
    /// posée entre deux bandes noires. En pochette carrée, ces bandes
    /// mangeaient un quart de l'image et noircissaient la couleur de fond —
    /// on ne garde que la bande 16:9 du milieu.
    var artwork: UIImage? {
        if let cached = Self.artworkCache.object(forKey: id as NSString) { return cached }
        guard let image = localThumbnail, let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var result = image
        if abs(w / h - 4.0 / 3.0) < 0.02 {
            let inner = w * 9 / 16
            let rect = CGRect(x: 0, y: (h - inner) / 2, width: w, height: inner).integral
            if let cropped = cg.cropping(to: rect) {
                result = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
            }
        }
        Self.artworkCache.setObject(result, forKey: id as NSString)
        return result
    }

    private static let artworkCache = NSCache<NSString, UIImage>()
}

// MARK: - Couleur dominante

private extension UIImage {
    /// Couleur moyenne, assombrie pour que le texte blanc reste lisible.
    var averageColor: UIColor? {
        guard let input = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: kCFNull as Any]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                blue: CGFloat(pixel[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(s * 1.3, 0.8), brightness: min(max(b, 0.3), 0.55), alpha: 1)
    }
}
