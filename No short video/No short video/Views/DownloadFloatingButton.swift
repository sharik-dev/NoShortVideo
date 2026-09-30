//
//  DownloadFloatingButton.swift
//  No short video
//
//  Created by Sharik Mohamed on 30/09/2026.
//

import SwiftUI

/// Bouton flottant ⬇︎ : télécharge ce qui est à l'écran pour l'avoir hors
/// ligne — la vidéo en MP4 sous le bouton PiP de YouTube, le morceau en MP3
/// dans YouTube Music (le bouton porte alors la mention « MP3 »).
///
/// Il porte lui-même la progression (anneau autour de l'icône) et observe seul
/// le service : si ContentView l'observait, chaque point de pourcentage
/// redessinerait tout l'écran, webviews comprises.
struct DownloadFloatingButton: View {

    var format: DownloadFormat = .mp4
    /// Identifiant du média à l'écran, s'il est connu : l'anneau suit alors
    /// son téléchargement à lui. Sinon, le dernier téléchargement du format.
    var videoId: String? = nil
    let action: () -> Void

    @ObservedObject private var downloads = VideoDownloadService.shared

    @State private var btnOffset: CGSize = .zero
    /// Le halo rouge respire doucement : c'est la fonction phare de l'écran.
    @State private var glowing = false
    @GestureState private var btnDrag: CGSize = .zero

    private var job: DownloadJob? {
        if let videoId { return downloads.job(for: videoId) }
        return downloads.jobs.last { $0.format == format && !$0.isOver }
    }

    var body: some View {
        Button {
            guard job == nil else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                if let job {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 3)
                        .frame(width: 26, height: 26)
                    Circle()
                        .trim(from: 0, to: max(0.04, job.progress))
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 26, height: 26)
                        .animation(.easeInOut(duration: 0.25), value: job.progress)
                    Image(systemName: job.phase == .downloading ? "arrow.down" : "gearshape.fill")
                        .font(.system(size: 10, weight: .bold))
                } else if format == .mp3 {
                    VStack(spacing: 0) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold))
                        Text("MP3")
                            .font(.system(size: 8, weight: .heavy))
                    }
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(Color(.label))
            .frame(width: 38, height: 38)
            .background(glassBackground)
        }
        .buttonStyle(.plain)
        .offset(x: btnOffset.width + btnDrag.width, y: btnOffset.height + btnDrag.height)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .updating($btnDrag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    btnOffset.width  += value.translation.width
                    btnOffset.height += value.translation.height
                }
        )
        .transition(.scale.combined(with: .opacity))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }

    // Même verre que `PiPFloatingButton`, pour que les deux se lisent comme une
    // paire — mais cerclé et auréolé de rouge : le téléchargement est la
    // fonction qu'on veut faire remarquer.
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [.red.opacity(0.9), .red.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .red.opacity(glowing ? 0.75 : 0.4), radius: glowing ? 10 : 6)
            .shadow(color: .red.opacity(glowing ? 0.35 : 0.15), radius: glowing ? 18 : 10)
    }
}

/// La pastille de progression en haut de l'écran, avec sa propre observation
/// du service (même raison que le bouton flottant).
///
/// Un appui la réduit en petit carré flottant, déplaçable au doigt, qui garde
/// l'anneau et le pourcentage ; un appui sur le carré la rouvre. Le choix est
/// mémorisé : le téléchargement suivant arrive directement en carré.
struct DownloadPillOverlay: View {

    @ObservedObject private var downloads = VideoDownloadService.shared
    var onOpenLibrary: () -> Void

    @AppStorage("downloadPillCollapsed") private var collapsed = false
    @State private var squareOffset: CGSize = .zero
    @GestureState private var squareDrag: CGSize = .zero

    var body: some View {
        if let job = downloads.activeJob {
            Group {
                if collapsed {
                    square(job)
                } else {
                    VStack {
                        DownloadProgressPill(
                            job: job,
                            onTap: { withAnimation(.spring(response: 0.35)) { collapsed = true } },
                            onClose: { downloads.dismiss(job.id) }
                        )
                        .padding(.top, 6)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4), value: job.id)
        }
    }

    // MARK: - Carré flottant

    private func square(_ job: DownloadJob) -> some View {
        VStack {
            HStack {
                Spacer()
                SquareProgress(job: job)
                    .offset(x: squareOffset.width + squareDrag.width,
                            y: squareOffset.height + squareDrag.height)
                    // Terminé : le carré mène à la bibliothèque, où la vidéo
                    // vient d'arriver. Sinon il rouvre la pastille.
                    .onTapGesture {
                        if job.phase == .finished {
                            downloads.dismiss(job.id)
                            onOpenLibrary()
                        } else {
                            withAnimation(.spring(response: 0.35)) { collapsed = false }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .updating($squareDrag) { v, s, _ in s = v.translation }
                            .onEnded { v in
                                squareOffset.width  += v.translation.width
                                squareOffset.height += v.translation.height
                            }
                    )
                    .padding(.trailing, 14)
                    .padding(.top, 60)
            }
            Spacer()
        }
        .transition(.scale(scale: 0.4, anchor: .topTrailing).combined(with: .opacity))
    }
}

/// Le carré lui-même : anneau de progression et pourcentage, en verre comme
/// les autres boutons flottants.
private struct SquareProgress: View {
    let job: DownloadJob

    var body: some View {
        ZStack {
            switch job.phase {
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            case .preparing, .downloading:
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: max(0.03, job.progress))
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 38, height: 38)
                    .animation(.easeInOut(duration: 0.25), value: job.progress)
                Text("\(Int((job.progress * 100).rounded()))")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
            }
        }
        .foregroundStyle(Color(.label))
        .frame(width: 54, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
