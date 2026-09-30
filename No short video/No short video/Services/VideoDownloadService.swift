//
//  VideoDownloadService.swift
//  No short video
//
//  Created by Sharik Mohamed on 30/09/2026.
//

import AVFoundation
import Combine
import UIKit

/// Un téléchargement en cours, tel que l'affiche la pastille de progression.
struct DownloadJob: Identifiable, Equatable {
    enum Phase: Equatable {
        /// Le site convertit la vidéo (`provider` = site en cours d'essai).
        case preparing(DownloadProvider)
        /// Le MP4 arrive sur le téléphone.
        case downloading
        case finished
        case failed
    }

    let id: String          // identifiant YouTube
    let title: String
    /// MP4 (YouTube) ou MP3 (YouTube Music).
    var format: DownloadFormat = .mp4
    var phase: Phase
    /// 0…1, propre à la phase en cours.
    var progress: Double
    var receivedBytes: Int64 = 0
    var expectedBytes: Int64 = 0
}

/// Télécharge une vidéo YouTube pour la lecture hors ligne, sans jamais montrer
/// de site à l'utilisateur.
///
/// 1. `DownloadResolver` pilote ytdown dans une webview cachée ; s'il échoue,
///    YT1s prend le relais.
/// 2. Le MP4 obtenu est rapatrié par `URLSession`, avec une vraie progression.
/// 3. Il atterrit dans `Documents/Downloads` et dans la bibliothèque (le même
///    magasin que les favoris), marqué « Hors ligne ». Le bouton bibliothèque
///    reçoit une pastille rouge tant qu'on ne l'a pas ouverte.
final class VideoDownloadService: NSObject, ObservableObject {

    static let shared = VideoDownloadService()

    @Published private(set) var jobs: [DownloadJob] = []

    /// Téléchargements terminés que l'utilisateur n'a pas encore vus : la
    /// pastille rouge du bouton bibliothèque. Remis à zéro à son ouverture.
    /// Un compteur par bibliothèque : un MP3 arrivé n'a rien à signaler côté
    /// vidéos.
    static let unseenKey = "unseenDownloads"
    static let unseenMusicKey = "unseenMusicDownloads"

    /// Chaque format a sa bibliothèque : les MP4 avec les favoris YouTube, les
    /// MP3 avec les morceaux de YouTube Music.
    private func storage(for format: DownloadFormat) -> VideoStorageService {
        format == .mp3 ? .music : .shared
    }
    private var resolver: DownloadResolver?
    private var tasks: [Int: String] = [:]                       // taskIdentifier → videoId
    private var transfers: [String: CheckedContinuation<URL, Error>] = [:]
    private var backgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    #if DEBUG
    /// Force un seul site, pour tester YT1s sans que ytdown réussisse avant.
    var debugOnlyProvider: DownloadProvider?
    #endif

    /// Travail visible dans la pastille : en cours, ou tout juste fini/échoué.
    var activeJob: DownloadJob? { jobs.last }


    // MARK: - Lancement

    func start(videoId: String, title: String, duration: Double, format: DownloadFormat = .mp4) {
        guard !jobs.contains(where: { $0.id == videoId && !$0.isOver }) else { return }
        jobs.removeAll { $0.id == videoId }
        jobs.append(DownloadJob(id: videoId, title: title, format: format,
                                phase: .preparing(.ytdown), progress: 0))

        // Quelques minutes de grâce si l'app passe en arrière-plan en cours de
        // route : la conversion et le transfert ont le temps de finir.
        backgroundTasks[videoId] = UIApplication.shared.beginBackgroundTask(withName: "download-\(videoId)") { [weak self] in
            self?.endBackgroundTask(videoId)
        }

        Task { await run(videoId: videoId, title: title, duration: duration, format: format) }
    }

    func job(for videoId: String) -> DownloadJob? {
        jobs.first { $0.id == videoId && !$0.isOver }
    }

    func dismiss(_ videoId: String) {
        jobs.removeAll { $0.id == videoId }
    }

    private func run(videoId: String, title: String, duration: Double, format: DownloadFormat) async {
        defer { endBackgroundTask(videoId) }

        var providers = DownloadProvider.allCases
        #if DEBUG
        if let only = debugOnlyProvider { providers = [only] }
        #endif

        for provider in providers {
            update(videoId) { $0.phase = .preparing(provider); $0.progress = 0 }
            do {
                let media = try await resolve(provider: provider, videoId: videoId, format: format)
                update(videoId) { $0.phase = .downloading; $0.progress = 0 }
                let file = try await transfer(media, videoId: videoId, format: format)
                // La page ne donne pas toujours la durée : le fichier, lui, la connaît.
                var length = duration
                if length <= 0, let d = try? await AVURLAsset(url: file).load(.duration).seconds, d.isFinite {
                    length = d
                }
                save(videoId: videoId, title: title, duration: length, file: file, format: format)
                update(videoId) { $0.phase = .finished; $0.progress = 1 }
                let key = format == .mp3 ? Self.unseenMusicKey : Self.unseenKey
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
                debugLog("[Download] done via \(provider.displayName): \(file.lastPathComponent)")
                scheduleDismiss(videoId, after: 4)
                return
            } catch {
                debugLog("[Download] \(provider.displayName) failed for \(videoId): \(error)")
                // Site suivant.
            }
        }

        update(videoId) { $0.phase = .failed }
        debugLog("[Download] all providers failed for \(videoId)")
        scheduleDismiss(videoId, after: 6)
    }

    // MARK: - Étape 1 : faire convertir par le site

    private func resolve(provider: DownloadProvider, videoId: String,
                         format: DownloadFormat) async throws -> ResolvedMedia {
        let resolver = DownloadResolver(provider: provider, videoId: videoId, format: format) { [weak self] value in
            guard let self, let job = self.jobs.first(where: { $0.id == videoId }),
                  abs(value - job.progress) >= 0.01 else { return }
            self.update(videoId) { $0.progress = value }
        }
        self.resolver = resolver
        defer { self.resolver = nil }
        return try await resolver.resolve()
    }

    // MARK: - Étape 2 : rapatrier le MP4

    private func transfer(_ media: ResolvedMedia, videoId: String,
                          format: DownloadFormat) async throws -> URL {
        var request = URLRequest(url: media.fileURL)
        request.setValue(DownloadResolver.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(media.referer.absoluteString, forHTTPHeaderField: "Referer")
        let cookies = media.cookies.filter { cookie in
            guard let host = media.fileURL.host else { return false }
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        HTTPCookie.requestHeaderFields(with: cookies).forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let tmp = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let task = session.downloadTask(with: request)
            tasks[task.taskIdentifier] = videoId
            transfers[videoId] = cont
            task.resume()
        }

        // Un « MP4 » de quelques Ko est une page d'erreur déguisée.
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
        guard size > 50_000 else {
            try? FileManager.default.removeItem(at: tmp)
            throw DownloadResolverError.site("file too small (\(size) bytes)")
        }

        let dest = SavedVideo.downloadsDirectory
            .appendingPathComponent("\(videoId).\(format.fileExtension)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    // MARK: - Étape 3 : ranger dans la bibliothèque

    private func save(videoId: String, title: String, duration: Double, file: URL,
                      format: DownloadFormat) {
        let storage = storage(for: format)
        let existing = storage.loadAll().first { $0.id == videoId }
        let video = SavedVideo(
            id: videoId,
            // Un favori garde le titre qu'il avait.
            title: existing?.title ?? title,
            thumbnailURL: SavedVideo.thumbnailURL(for: videoId),
            url: existing?.url ?? (format == .mp3
                ? "https://music.youtube.com/watch?v=\(videoId)"
                : "https://m.youtube.com/watch?v=\(videoId)"),
            lastTime: existing?.lastTime ?? 0,
            duration: duration,
            dateAdded: existing?.dateAdded ?? Date(),
            folder: existing?.folder ?? "",
            localFileName: file.lastPathComponent
        )
        storage.save(video)
        cacheThumbnail(videoId: videoId)
    }

    /// La miniature est aussi rapatriée : hors ligne, `AsyncImage` n'a rien à
    /// charger et la liste n'afficherait que des rectangles gris.
    private func cacheThumbnail(videoId: String) {
        guard let url = URL(string: SavedVideo.thumbnailURL(for: videoId)) else { return }
        let dest = SavedVideo.downloadsDirectory.appendingPathComponent("\(videoId).jpg")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data { try? data.write(to: dest, options: .atomic) }
        }.resume()
    }

    // MARK: - Utilitaires

    private func update(_ videoId: String, _ change: (inout DownloadJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == videoId }) else { return }
        change(&jobs[i])
    }

    private func scheduleDismiss(_ videoId: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let job = self.jobs.first(where: { $0.id == videoId }), job.isOver else { return }
            self.dismiss(videoId)
        }
    }

    private func endBackgroundTask(_ videoId: String) {
        guard let id = backgroundTasks.removeValue(forKey: videoId) else { return }
        UIApplication.shared.endBackgroundTask(id)
    }
}

extension DownloadJob {
    var isOver: Bool { phase == .finished || phase == .failed }
}

// MARK: - URLSessionDownloadDelegate

extension VideoDownloadService: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let id = downloadTask.taskIdentifier
        MainActor.assumeIsolated {
            guard let videoId = tasks[id] else { return }
            // URLSession rappelle des dizaines de fois par seconde : on ne
            // republie qu'à chaque point de pourcentage (ou 512 Ko sans taille
            // connue). Sans ce filtre, l'écran se redessinait en continu.
            guard let job = jobs.first(where: { $0.id == videoId }) else { return }
            let progress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : job.progress
            let moved = totalBytesExpectedToWrite > 0
                ? progress - job.progress >= 0.01
                : totalBytesWritten - job.receivedBytes >= 512 * 1024
            guard moved || job.expectedBytes == 0 && totalBytesExpectedToWrite > 0 else { return }
            update(videoId) {
                $0.receivedBytes = totalBytesWritten
                $0.expectedBytes = max(totalBytesExpectedToWrite, 0)
                $0.progress = progress
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Le fichier temporaire disparaît au retour de cette méthode : on le
        // met à l'abri tout de suite.
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".download")
        let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        let id = downloadTask.taskIdentifier

        MainActor.assumeIsolated {
            guard let videoId = tasks.removeValue(forKey: id),
                  let cont = transfers.removeValue(forKey: videoId) else { return }
            if moved && (200..<300).contains(status) {
                cont.resume(returning: keep)
            } else {
                try? FileManager.default.removeItem(at: keep)
                cont.resume(throwing: DownloadResolverError.site("HTTP \(status)"))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let videoId = tasks.removeValue(forKey: id),
                  let cont = transfers.removeValue(forKey: videoId) else { return }
            cont.resume(throwing: error)
        }
    }
}

/// Trace DEBUG dans `Documents/download-debug.log` : la console du simulateur
/// perd des lignes, un fichier non.
func debugLog(_ message: String) {
    #if DEBUG
    NSLog("%@", message)
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("download-debug.log")
    let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
    #endif
}
