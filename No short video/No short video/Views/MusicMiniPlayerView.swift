//
//  MusicMiniPlayerView.swift
//  No short video
//

import SwiftUI

/// Bandeau de lecture affiché pendant qu'on navigue ailleurs que sur YouTube
/// Music. Il rappelle ce qui joue et donne les deux gestes demandés : mettre en
/// pause, ou abandonner la session. Toucher le titre ramène sur YouTube Music.
///
/// Deux formes, au choix de l'utilisateur (bouton « punaise ») :
/// - **ancré** : la barre pleine largeur, posée au-dessus de la barre d'outils ;
/// - **flottant** : une pastille compacte qu'on déplace où l'on veut, pour
///   libérer le bas de l'écran quand la page en a besoin (le fil d'Instagram,
///   les commentaires YouTube, un formulaire).
struct MusicMiniPlayerView: View {

    @ObservedObject var musicVM: MusicWebViewModel
    /// Forme compacte et déplaçable. Le déplacement lui-même est géré par la
    /// vue parente, qui seule connaît la taille de l'écran.
    var isFloating: Bool = false
    /// Revenir à YouTube Music.
    var onOpen: () -> Void
    /// Basculer entre ancré et flottant.
    var onToggleFloat: () -> Void = {}

    @AppStorage("appLanguage") private var lang: String = "en"

    var body: some View {
        if isFloating { floating } else { docked }
    }

    // MARK: - Ancré

    private var docked: some View {
        HStack(spacing: 12) {

            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: musicVM.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
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

            floatToggle

            Button { musicVM.togglePlayPause() } label: {
                Image(systemName: musicVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(musicVM.isPlaying ? t("Pause", "Pause") : t("Lecture", "Play"))

            Button { musicVM.discard() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Arrêter la musique", "Stop music"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - Flottant

    /// Pastille compacte : ouvrir, lecture/pause, ré-ancrer. Le titre disparaît
    /// — c'est tout l'intérêt de la forme flottante, ne presque rien couvrir.
    private var floating: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                Image(systemName: musicVM.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Ouvrir YouTube Music", "Open YouTube Music"))

            Button { musicVM.togglePlayPause() } label: {
                Image(systemName: musicVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(musicVM.isPlaying ? t("Pause", "Pause") : t("Lecture", "Play"))

            floatToggle
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background(cornerRadius: 22))
    }

    // MARK: - Bouton flotter / ancrer

    private var floatToggle: some View {
        Button(action: onToggleFloat) {
            Image(systemName: isFloating ? "pin.slash.fill" : "pin.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFloating
            ? t("Ancrer le bandeau en bas", "Dock the banner")
            : t("Rendre le bandeau flottant", "Make the banner float"))
    }

    // MARK: - Helpers

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    private var accent: Color { Color(red: 1, green: 0.18, blue: 0.33) }

    private var title: String {
        musicVM.trackTitle.isEmpty ? "YouTube Music" : musicVM.trackTitle
    }

    private func background(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
    }
}
