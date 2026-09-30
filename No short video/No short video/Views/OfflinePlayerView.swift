//
//  OfflinePlayerView.swift
//  No short video
//
//  Created by Sharik Mohamed on 30/09/2026.
//

import AVKit
import SwiftUI

/// Lecture d'une vidéo téléchargée, sans réseau.
///
/// `AVPlayerViewController` plutôt que `VideoPlayer` de SwiftUI : il apporte le
/// plein écran, le PiP et AirPlay sans rien réécrire. La position est
/// enregistrée en continu, comme pour les favoris en ligne, et la lecture
/// reprend là où on l'avait laissée.
struct OfflinePlayerView: UIViewControllerRepresentable {

    let video: SavedVideo
    var storage: VideoStorageService = .shared

    func makeCoordinator() -> Coordinator { Coordinator(video: video, storage: storage) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.player = context.coordinator.player
        // Un MP3 n'a pas d'image : on montre la pochette (miniature) plutôt
        // qu'un écran noir.
        if video.localFileName?.hasSuffix(".mp3") == true,
           let artwork = video.localThumbnail,
           let overlay = controller.contentOverlayView {
            let imageView = UIImageView(image: artwork)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
                imageView.widthAnchor.constraint(equalTo: overlay.widthAnchor, multiplier: 0.86),
            ])
        }
        context.coordinator.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        let player: AVPlayer
        private var video: SavedVideo
        private let storage: VideoStorageService
        private var observer: Any?

        init(video: SavedVideo, storage: VideoStorageService) {
            self.video = video
            self.storage = storage
            self.player = AVPlayer(url: video.localFileURL ?? URL(fileURLWithPath: "/dev/null"))
        }

        func play() {
            // Reprise, sauf si la vidéo avait été vue jusqu'au bout.
            if video.lastTime > 1, video.duration <= 0 || video.lastTime < video.duration - 5 {
                player.seek(to: CMTime(seconds: video.lastTime, preferredTimescale: 600))
            }
            player.play()
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.persist() }
            }
        }

        func stop() {
            persist()
            player.pause()
            if let observer { player.removeTimeObserver(observer) }
            observer = nil
        }

        private func persist() {
            let time = player.currentTime().seconds
            guard time.isFinite, time > 0 else { return }
            video.lastTime = time
            if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                video.duration = d
            }
            storage.save(video)
        }
    }
}

/// Plein écran avec un bouton de fermeture : le lecteur AVKit intégré n'en a
/// pas quand il est présenté en `fullScreenCover`.
struct OfflinePlayerScreen: View {
    let video: SavedVideo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            OfflinePlayerView(video: video)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
    }
}
