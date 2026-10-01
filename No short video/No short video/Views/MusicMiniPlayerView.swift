//
//  MusicMiniPlayerView.swift
//  No short video
//

import SwiftUI

/// Bandeau de lecture affiché pendant qu'on navigue ailleurs que sur YouTube
/// Music. Il rappelle ce qui joue et donne les gestes utiles : mettre en pause,
/// abandonner la session, ou **masquer** le bandeau. Toucher le titre ramène
/// sur YouTube Music.
///
/// Masqué, le bandeau devient une bulle ronde (`MusicBubble`) que ContentView
/// laisse déplacer au doigt : la page récupère tout le bas de l'écran (le fil
/// d'Instagram, les commentaires, un formulaire). Toucher la bulle rouvre le
/// bandeau.
struct MusicMiniPlayerView: View {

    @ObservedObject var musicVM: MusicWebViewModel
    /// Revenir à YouTube Music.
    var onOpen: () -> Void
    /// Réduire le bandeau en bulle flottante.
    var onHide: () -> Void

    @AppStorage("appLanguage") private var lang: String = "en"

    var body: some View {
        HStack(spacing: 6) {

            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: musicVM.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MusicGlass.accent)
                        .shadow(color: MusicGlass.accent.opacity(0.6), radius: 5)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !musicVM.artist.isEmpty {
                            Text(musicVM.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            MusicGlass.iconButton(musicVM.isPlaying ? "pause.fill" : "play.fill",
                                  label: musicVM.isPlaying ? t("Pause", "Pause") : t("Lecture", "Play")) {
                musicVM.togglePlayPause()
            }

            MusicGlass.iconButton("xmark", size: 13, dimmed: true,
                                  label: t("Arrêter la musique", "Stop music")) {
                musicVM.discard()
            }

            MusicGlass.hideButton(label: t("Masquer le bandeau", "Hide the banner"), action: onHide)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .musicGlass(cornerRadius: 20)
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    private var title: String {
        musicVM.trackTitle.isEmpty ? "YouTube Music" : musicVM.trackTitle
    }
}

// MARK: - Bulle flottante

/// Le bandeau masqué : une bulle ronde, en verre comme les autres boutons
/// flottants, qui ne couvre presque rien. Elle porte ce qu'il faut pour savoir
/// que la musique tourne (onde animée, pochette, anneau de progression) et se
/// rouvre au toucher. L'appui et le déplacement sont gérés ensemble par
/// ContentView (`floatingDrag`) : un bouton ici se déclencherait au lâcher
/// d'un glissé.
struct MusicBubble<Content: View>: View {

    var isPlaying: Bool
    /// Anneau de progression autour de la bulle (MP3 hors ligne), s'il est connu.
    var progress: Double? = nil
    @ViewBuilder var content: Content

    @AppStorage("appLanguage") private var lang: String = "en"

    var body: some View {
        ZStack {
            content
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            if let progress {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(MusicGlass.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
            }
        }
        .frame(width: 48, height: 48)
        .padding(3)
        .musicGlass(cornerRadius: 27, glowing: isPlaying)
        .contentShape(Circle())
        .accessibilityLabel(lang == "fr" ? "Afficher le lecteur" : "Show the player")
    }
}

/// Contenu par défaut de la bulle YouTube Music : l'onde qui bouge tant que ça
/// joue, une note à l'arrêt.
struct MusicBubbleIcon: View {
    var isPlaying: Bool

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "music.note")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MusicGlass.accent)
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .shadow(color: MusicGlass.accent.opacity(0.6), radius: 5)
    }
}

// MARK: - Verre commun

/// Le verre des bandeaux musique : **le même que la barre d'outils**
/// (`ToolbarView`) — matière fine, liseré blanc en dégradé, halo clair vers le
/// haut. Les deux bandeaux (YouTube Music et MP3 hors ligne) l'utilisent, pour
/// qu'aucun ne se lise comme une pièce rapportée grise posée sur la page.
enum MusicGlass {

    static let accent = Color(red: 1, green: 0.18, blue: 0.33)

    /// Bouton rond d'icône, blanc lumineux comme ceux de la barre d'outils.
    static func iconButton(_ icon: String,
                           size: CGFloat = 15,
                           dimmed: Bool = false,
                           label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(dimmed ? 0.65 : 1))
                .shadow(color: .white.opacity(dimmed ? 0 : 0.4), radius: 4)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// « Masquer », toujours le dernier à droite : réduit le bandeau en bulle.
    static func hideButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.12)))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct MusicGlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var glowing: Bool

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: glowing ? MusicGlass.accent.opacity(0.35) : .white.opacity(0.16), radius: 14)
                .shadow(color: .white.opacity(0.08), radius: 28, y: -8)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
        )
    }
}

extension View {
    func musicGlass(cornerRadius: CGFloat, glowing: Bool = false) -> some View {
        modifier(MusicGlassBackground(cornerRadius: cornerRadius, glowing: glowing))
    }
}
