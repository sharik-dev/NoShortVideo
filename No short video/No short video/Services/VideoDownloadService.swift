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
        /// Interrompu (app quittée, réseau perdu) : reprendra au prochain
        /// retour dans l'app.
        case waiting
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

/// Un téléchargement demandé et pas encore arrivé. Écrit sur le disque : c'est
/// ce qui permet de le reprendre après que l'app a été quittée, suspendue ou
/// tuée — la liste `jobs`, elle, ne vit qu'en mémoire.
struct PendingDownload: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var duration: Double
    var format: DownloadFormat
    /// Reprises après une coupure réseau ou une erreur en arrière-plan. Au-delà
    /// de `maxRetries`, on abandonne : une vidéo qui casse à chaque fois ne
    /// doit pas se relancer indéfiniment.
    var retries: Int = 0
    /// L'élément a été créé dans la bibliothèque par ce téléchargement (ce
    /// n'était pas un favori) : l'annuler l'en retire.
    var addedToLibrary: Bool = false
}

/// Télécharge une vidéo YouTube pour la lecture hors ligne, sans jamais montrer
/// de site à l'utilisateur.
///
/// 1. `DownloadResolver` pilote ytdown dans une webview cachée ; s'il échoue,
///    YT1s prend le relais.
/// 2. Le MP4 obtenu est rapatrié par une `URLSession` **d'arrière-plan** : le
///    transfert continue app suspendue, et même si iOS la tue pour libérer de
///    la mémoire.
/// 3. Il atterrit dans `Documents/Downloads` et dans la bibliothèque (le même
///    magasin que les favoris), marqué « Hors ligne ». Le bouton bibliothèque
///    reçoit une pastille rouge tant qu'on ne l'a pas ouverte.
///
/// Chaque demande est d'abord inscrite dans une file sur le disque (`pending`)
/// et apparaît aussitôt « En attente » dans la bibliothèque. Les demandes
/// passent une par une. Une demande coupée en route — app quittée pendant la
/// conversion, balayée du sélecteur d'apps, réseau perdu — reste dans la file
/// et repart au prochain retour au premier plan : par la reprise du transfert
/// (`resumeData`) si le serveur l'accepte encore, sinon depuis la conversion.
///
/// La conversion ne peut pas tourner app fermée : iOS gèle toute webview en
/// arrière-plan. Seul le transfert survit à la sortie de l'app.
final class VideoDownloadService: NSObject, ObservableObject {

    static let shared = VideoDownloadService()

    @Published private(set) var jobs: [DownloadJob] = []

    /// La file persistée, dans l'ordre où elle sera servie.
    @Published private(set) var pending: [PendingDownload] = []

    /// Téléchargements terminés que l'utilisateur n'a pas encore vus : la
    /// pastille rouge du bouton bibliothèque. Remis à zéro à son ouverture.
    /// Un compteur par bibliothèque : un MP3 arrivé n'a rien à signaler côté
    /// vidéos.
    static let unseenKey = "unseenDownloads"
    static let unseenMusicKey = "unseenMusicDownloads"

    private static let maxRetries = 3
    private static let sessionIdentifier = (Bundle.main.bundleIdentifier ?? "noshort") + ".downloads"

    /// Chaque format a sa bibliothèque : les MP4 avec les favoris YouTube, les
    /// MP3 avec les morceaux de YouTube Music.
    private func storage(for format: DownloadFormat) -> VideoStorageService {
        format == .mp3 ? .music : .shared
    }
    private var resolver: DownloadResolver?
    /// Transferts attendus par `run` (videoId → suite du pipeline). Un
    /// transfert sans continuation est un orphelin, lancé par un processus
    /// précédent de l'app : le délégué le termine lui-même.
    private var transfers: [String: CheckedContinuation<URL, Error>] = [:]
    /// Transferts orphelins encore en vol, retrouvés au lancement.
    private var orphans: Set<String> = []
    /// Données de reprise du dernier transfert échoué, le temps que `run` les
    /// range.
    private var lastResumeData: [String: Data] = [:]

    /// La demande en cours de traitement (conversion ou transfert).
    private var current: String?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Le sursis d'arrière-plan a expiré pendant la conversion.
    private var backgroundExpired = false
    /// Après une interruption, on attend le prochain retour au premier plan :
    /// relancer aussitôt, réseau coupé, tournerait en boucle.
    private var paused = false
    /// `restore` a fait le point avec la session : avant, on risquerait de
    /// relancer une demande dont le transfert est encore en vol.
    private var restored = false

    /// Rendu par `application(_:handleEventsForBackgroundURLSession:)`, à
    /// appeler quand la session a livré tous ses événements.
    var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    #if DEBUG
    /// Force un seul site, pour tester YT1s sans que ytdown réussisse avant.
    var debugOnlyProvider: DownloadProvider?
    #endif

    /// L'interface de téléchargement manuel — ⬇︎, pastille, « Hors ligne ».
    /// Réservée aux builds DEBUG (usage perso) ; la version App Store ne
    /// télécharge que les favoris musicaux, en silence. `-storeCapture YES`
    /// la masque aussi en DEBUG, pour capturer les écrans du store.
    static var showsManualDownloads: Bool {
        #if DEBUG
        !UserDefaults.standard.bool(forKey: "storeCapture")
        #else
        false
        #endif
    }

    /// Travail visible dans la pastille : en cours, ou tout juste fini/échoué.
    var activeJob: DownloadJob? { jobs.last }

    private override init() {
        super.init()
        pending = Self.loadQueue()
    }

    // MARK: - Lancement

    func start(videoId: String, title: String, duration: Double, format: DownloadFormat = .mp4) {
        paused = false
        guard !isPending(videoId) else { return pump() }

        let storage = storage(for: format)
        var entry = PendingDownload(id: videoId, title: title, duration: duration, format: format)
        // Visible dans la bibliothèque dès maintenant, avec son statut.
        if !storage.loadAll().contains(where: { $0.id == videoId }) {
            storage.save(SavedVideo(
                id: videoId, title: title,
                thumbnailURL: SavedVideo.thumbnailURL(for: videoId),
                url: Self.pageURL(videoId: videoId, format: format),
                lastTime: 0, duration: duration, dateAdded: Date()
            ))
            entry.addedToLibrary = true
        }
        pending.append(entry)
        saveQueue()

        jobs.removeAll { $0.id == videoId }
        pump()
    }

    /// Au lancement de l'app, avant tout : recrée la session d'arrière-plan
    /// (iOS lui livre alors ce qui s'est passé pendant notre absence) et
    /// repère les transferts encore en vol.
    func restore() {
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for task in tasks {
                    guard let id = task.taskDescription,
                          let entry = self.pending.first(where: { $0.id == id }),
                          task.state == .running || task.state == .suspended
                    else { task.cancel(); continue }
                    self.orphans.insert(id)
                    if !self.jobs.contains(where: { $0.id == id }) {
                        self.jobs.append(DownloadJob(id: id, title: entry.title, format: entry.format,
                                                     phase: .downloading, progress: 0))
                    }
                    task.resume()
                }
                self.restored = true
                debugLog("[Download] restored: \(self.pending.count) pending, \(self.orphans.count) in flight")
                self.downloadDueFavorites()
                self.pump()
            }
        }
    }

    /// Retour au premier plan : on reprend la file là où elle en était.
    func resumePending() {
        paused = false
        downloadDueFavorites()
        pump()
    }

    // MARK: - Favoris musicaux

    /// Un morceau mis en favori se télécharge tout seul, en MP3, cinq minutes
    /// plus tard — sans bouton, sans pastille, sans badge. C'est désormais la
    /// seule façon dont l'app télécharge quelque chose.
    ///
    /// Cinq minutes plutôt qu'aussitôt : un favori retiré dans la foulée (appui
    /// par erreur) ne coûte rien.
    static let favoriteDelay: TimeInterval = 5 * 60
    /// Avant de retenter un morceau sur lequel tous les sites ont échoué :
    /// sans ce délai, il repartirait à chaque retour dans l'app.
    private static let giveUpDelay: TimeInterval = 24 * 60 * 60
    private static let gaveUpKey = "favoriteDownloadsGaveUp"
    private var favoriteTimer: Timer?

    /// Lance les favoris musicaux dont le délai est écoulé, et arme un réveil
    /// pour le prochain. Le délai se compte depuis `dateAdded`, écrit sur le
    /// disque : une app quittée entre-temps rattrape son retard au retour.
    func downloadDueFavorites() {
        favoriteTimer?.invalidate()
        favoriteTimer = nil
        guard restored else { return }

        let now = Date()
        let gaveUp = Self.gaveUp().filter { now.timeIntervalSince($0.value) < Self.giveUpDelay }
        Self.saveGaveUp(gaveUp)
        var next: Date?
        for track in VideoStorageService.music.loadAll()
        where !track.isOffline && !isPending(track.id) && gaveUp[track.id] == nil {
            let due = track.dateAdded.addingTimeInterval(Self.favoriteDelay)
            if due <= now {
                start(videoId: track.id, title: track.title, duration: track.duration, format: .mp3)
            } else {
                next = min(next ?? due, due)
            }
        }

        if let next {
            let timer = Timer(fire: next.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
                self?.downloadDueFavorites()
            }
            RunLoop.main.add(timer, forMode: .common)
            favoriteTimer = timer
        }
    }

    private static func gaveUp() -> [String: Date] {
        UserDefaults.standard.dictionary(forKey: gaveUpKey) as? [String: Date] ?? [:]
    }

    private static func saveGaveUp(_ value: [String: Date]) {
        UserDefaults.standard.set(value, forKey: gaveUpKey)
    }

    func cancel(_ videoId: String) {
        guard let entry = pending.first(where: { $0.id == videoId }) else { return }
        pending.removeAll { $0.id == videoId }
        saveQueue()
        Self.deleteResumeData(videoId)
        if entry.addedToLibrary, !(storage(for: entry.format).loadAll().first { $0.id == videoId }?.isOffline ?? false) {
            storage(for: entry.format).delete(videoId: videoId)
        }
        jobs.removeAll { $0.id == videoId }

        if current == videoId { resolver?.cancel() }
        transfers.removeValue(forKey: videoId)?.resume(throwing: CancellationError())
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == videoId }.forEach { $0.cancel() }
        }
        orphans.remove(videoId)
        debugLog("[Download] cancelled \(videoId)")
        pump()
    }

    func job(for videoId: String) -> DownloadJob? {
        jobs.first { $0.id == videoId && !$0.isOver }
    }

    /// Demandé mais pas encore arrivé — en cours ou en attente de son tour.
    func isPending(_ videoId: String) -> Bool {
        pending.contains { $0.id == videoId }
    }

    func dismiss(_ videoId: String) {
        jobs.removeAll { $0.id == videoId }
    }

    // MARK: - File

    /// Sert la demande suivante, s'il n'y en a pas déjà une en route.
    private func pump() {
        guard restored, !paused, current == nil, orphans.isEmpty,
              UIApplication.shared.applicationState == .active,
              let next = pending.first
        else { return }

        current = next.id
        backgroundExpired = false
        // Quelques minutes de grâce si l'app passe en arrière-plan pendant la
        // conversion. Le transfert, lui, n'en a pas besoin : la session
        // d'arrière-plan continue sans nous.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "download-\(next.id)") { [weak self] in
            guard let self else { return }
            if self.resolver != nil {
                self.backgroundExpired = true
                self.resolver?.cancel()
            }
            self.endBackgroundTask()
        }

        Task { await run(next) }
    }

    private func run(_ entry: PendingDownload) async {
        let videoId = entry.id
        defer {
            endBackgroundTask()
            if current == videoId { current = nil }
            pump()
        }

        jobs.removeAll { $0.id == videoId }
        jobs.append(DownloadJob(id: videoId, title: entry.title, format: entry.format,
                                phase: .preparing(.ytdown), progress: 0))

        // Reprise d'un transfert coupé : le lien du site n'a peut-être pas
        // encore expiré, on évite alors toute la conversion.
        if let data = Self.loadResumeData(videoId) {
            Self.deleteResumeData(videoId)
            update(videoId) { $0.phase = .downloading; $0.progress = 0 }
            do {
                let file = try await transfer(session.downloadTask(withResumeData: data), videoId: videoId,
                                              format: entry.format)
                await complete(entry, file: file, via: "resume")
                return
            } catch {
                guard isPending(videoId) else { return }       // annulé
                if isInterruption(error) { return interrupt(entry, error: error) }
                debugLog("[Download] resume failed for \(videoId): \(error) — converting again")
            }
        }

        var providers = DownloadProvider.allCases.filter { $0.supports(entry.format) }
        #if DEBUG
        if let only = debugOnlyProvider { providers = [only] }
        #endif

        for provider in providers {
            update(videoId) { $0.phase = .preparing(provider); $0.progress = 0 }
            do {
                let media = try await resolve(provider: provider, videoId: videoId, format: entry.format)
                update(videoId) { $0.phase = .downloading; $0.progress = 0 }
                let file = try await transfer(session.downloadTask(with: request(for: media)),
                                              videoId: videoId, format: entry.format)
                await complete(entry, file: file, via: provider.displayName)
                return
            } catch {
                guard isPending(videoId) else { return }       // annulé
                debugLog("[Download] \(provider.displayName) failed for \(videoId): \(error)")
                if isInterruption(error) { return interrupt(entry, error: error) }
                // Site suivant.
            }
        }

        fail(entry)
    }

    /// Une coupure qui ne dit rien de la vidéo elle-même : l'app a quitté le
    /// premier plan, ou le réseau a lâché. On réessaiera plus tard.
    private func isInterruption(_ error: Error) -> Bool {
        if backgroundExpired || UIApplication.shared.applicationState != .active { return true }
        guard let code = (error as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .backgroundSessionWasDisconnected, .dataNotAllowed,
                .internationalRoamingOff, .callIsActive].contains(code)
    }

    private func interrupt(_ entry: PendingDownload, error: Error) {
        let videoId = entry.id
        let resumeData = lastResumeData.removeValue(forKey: videoId)
            ?? (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        // Quitter l'app n'est pas la faute de la vidéo : seules les coupures
        // réseau comptent dans la limite de reprises.
        let counts = !backgroundExpired && UIApplication.shared.applicationState == .active
        guard bump(videoId, counts: counts) else { return fail(entry) }
        if let resumeData { Self.saveResumeData(resumeData, for: videoId) }
        paused = true
        update(videoId) { $0.phase = .waiting }
        scheduleDismiss(videoId, after: 6)
        debugLog("[Download] interrupted \(videoId) (resume data: \(resumeData != nil)): \(error)")
    }

    /// Compte une reprise ; `false` si la limite est atteinte.
    private func bump(_ videoId: String, counts: Bool) -> Bool {
        guard let i = pending.firstIndex(where: { $0.id == videoId }) else { return false }
        if counts { pending[i].retries += 1 }
        saveQueue()
        return pending[i].retries <= Self.maxRetries
    }

    private func fail(_ entry: PendingDownload) {
        pending.removeAll { $0.id == entry.id }
        saveQueue()
        Self.deleteResumeData(entry.id)
        // L'élément reste dans la bibliothèque ; un favori musical sera retenté
        // dans un jour (cf. `downloadDueFavorites`).
        if entry.format == .mp3 {
            var gaveUp = Self.gaveUp()
            gaveUp[entry.id] = Date()
            Self.saveGaveUp(gaveUp)
        }
        update(entry.id) { $0.phase = .failed }
        debugLog("[Download] all providers failed for \(entry.id)")
        scheduleDismiss(entry.id, after: 6)
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

    private func request(for media: ResolvedMedia) -> URLRequest {
        var request = URLRequest(url: media.fileURL)
        request.setValue(DownloadResolver.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(media.referer.absoluteString, forHTTPHeaderField: "Referer")
        let cookies = media.cookies.filter { cookie in
            guard let host = media.fileURL.host else { return false }
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        HTTPCookie.requestHeaderFields(with: cookies).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    private func transfer(_ task: URLSessionDownloadTask, videoId: String,
                          format: DownloadFormat) async throws -> URL {
        // La tâche porte l'identifiant de la vidéo : après une relance de
        // l'app, c'est tout ce qui reste pour savoir à qui elle appartient.
        task.taskDescription = videoId
        lastResumeData[videoId] = nil
        let tmp = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            transfers[videoId] = cont
            task.resume()
        }
        return try Self.place(tmp, videoId: videoId, format: format)
    }

    /// Range le fichier reçu dans `Documents/Downloads`, après avoir vérifié
    /// que c'est bien un média.
    private static func place(_ tmp: URL, videoId: String, format: DownloadFormat) throws -> URL {
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

    private func complete(_ entry: PendingDownload, file: URL, via source: String) async {
        let videoId = entry.id
        // La page ne donne pas toujours la durée : le fichier, lui, la connaît.
        var length = entry.duration
        if length <= 0, let d = try? await AVURLAsset(url: file).load(.duration).seconds, d.isFinite {
            length = d
        }
        save(videoId: videoId, title: entry.title, duration: length, file: file, format: entry.format)
        pending.removeAll { $0.id == videoId }
        saveQueue()
        Self.deleteResumeData(videoId)

        if !jobs.contains(where: { $0.id == videoId }) {
            jobs.append(DownloadJob(id: videoId, title: entry.title, format: entry.format,
                                    phase: .finished, progress: 1))
        }
        update(videoId) { $0.phase = .finished; $0.progress = 1 }
        // Un favori musical arrive en silence : pas de pastille rouge.
        if entry.format == .mp4 {
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.unseenKey) + 1,
                                      forKey: Self.unseenKey)
        }
        await ReviewPromptService.shared.recordSuccess()
        debugLog("[Download] done via \(source): \(file.lastPathComponent)")
        scheduleDismiss(videoId, after: 4)
    }

    private func save(videoId: String, title: String, duration: Double, file: URL,
                      format: DownloadFormat) {
        let storage = storage(for: format)
        let existing = storage.loadAll().first { $0.id == videoId }
        let video = SavedVideo(
            id: videoId,
            // Un favori garde le titre qu'il avait.
            title: existing?.title ?? title,
            thumbnailURL: SavedVideo.thumbnailURL(for: videoId),
            url: existing?.url ?? Self.pageURL(videoId: videoId, format: format),
            lastTime: existing?.lastTime ?? 0,
            duration: duration,
            dateAdded: existing?.dateAdded ?? Date(),
            folder: existing?.folder ?? "",
            localFileName: file.lastPathComponent
        )
        storage.save(video)
        cacheThumbnail(videoId: videoId)
    }

    private static func pageURL(videoId: String, format: DownloadFormat) -> String {
        format == .mp3
            ? "https://music.youtube.com/watch?v=\(videoId)"
            : "https://m.youtube.com/watch?v=\(videoId)"
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

    // MARK: - Transferts orphelins

    /// Un transfert lancé par un processus précédent de l'app vient d'aboutir.
    private func finishOrphan(_ videoId: String, tmp: URL?, status: Int) async {
        orphans.remove(videoId)
        defer { pump() }
        guard let entry = pending.first(where: { $0.id == videoId }) else {
            if let tmp { try? FileManager.default.removeItem(at: tmp) }
            return
        }
        do {
            guard let tmp, (200..<300).contains(status) else {
                if let tmp { try? FileManager.default.removeItem(at: tmp) }
                throw DownloadResolverError.site("HTTP \(status)")
            }
            let file = try Self.place(tmp, videoId: videoId, format: entry.format)
            await complete(entry, file: file, via: "background")
        } catch {
            // Le lien a sans doute expiré : on repartira de la conversion.
            debugLog("[Download] background transfer unusable for \(videoId): \(error)")
            dismiss(videoId)
            if !bump(videoId, counts: true) { fail(entry) }
        }
    }

    /// Un transfert orphelin a échoué — le plus souvent parce que
    /// l'utilisateur a balayé l'app du sélecteur, ce qui annule tout.
    private func failOrphan(_ videoId: String, error: Error) {
        orphans.remove(videoId)
        defer { pump() }
        guard let entry = pending.first(where: { $0.id == videoId }) else { return }
        let info = (error as NSError).userInfo
        if let data = info[NSURLSessionDownloadTaskResumeData] as? Data {
            Self.saveResumeData(data, for: videoId)
        }
        let reason = info[NSURLErrorBackgroundTaskCancelledReasonKey] as? Int
        let forceQuit = reason == NSURLErrorCancelledReasonUserForceQuitApplication
        dismiss(videoId)
        if !bump(videoId, counts: !forceQuit) { fail(entry) }
        debugLog("[Download] background transfer stopped for \(videoId) (force quit: \(forceQuit)): \(error)")
    }

    // MARK: - Persistance

    private static let queueDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var queueURL: URL { queueDirectory.appendingPathComponent("queue.json") }

    private static func loadQueue() -> [PendingDownload] {
        guard let data = try? Data(contentsOf: queueURL),
              let queue = try? JSONDecoder().decode([PendingDownload].self, from: data)
        else { return [] }
        return queue
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: Self.queueURL, options: .atomic)
    }

    private static func resumeDataURL(_ videoId: String) -> URL {
        queueDirectory.appendingPathComponent("\(videoId).resume")
    }

    private static func loadResumeData(_ videoId: String) -> Data? {
        try? Data(contentsOf: resumeDataURL(videoId))
    }

    private static func saveResumeData(_ data: Data, for videoId: String) {
        try? data.write(to: resumeDataURL(videoId), options: .atomic)
    }

    private static func deleteResumeData(_ videoId: String) {
        try? FileManager.default.removeItem(at: resumeDataURL(videoId))
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

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

extension DownloadJob {
    /// Plus rien ne bouge : la pastille propose de se fermer.
    var isOver: Bool { phase == .finished || phase == .failed || phase == .waiting }
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
        let description = downloadTask.taskDescription
        MainActor.assumeIsolated {
            guard let videoId = description else { return }
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
        var status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        // Un site qui renvoie sa propre page au lieu du fichier : c'est un
        // échec, sinon on rangerait du HTML sous le nom d'une vidéo.
        if downloadTask.response?.mimeType?.lowercased().hasPrefix("text/") == true { status = 415 }
        let description = downloadTask.taskDescription

        MainActor.assumeIsolated {
            guard let videoId = description else { return }
            guard let cont = transfers.removeValue(forKey: videoId) else {
                Task { await finishOrphan(videoId, tmp: moved ? keep : nil, status: status) }
                return
            }
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
        let description = task.taskDescription
        MainActor.assumeIsolated {
            guard let videoId = description else { return }
            guard let cont = transfers.removeValue(forKey: videoId) else {
                return failOrphan(videoId, error: error)
            }
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                lastResumeData[videoId] = data
            }
            cont.resume(throwing: error)
        }
    }

    /// La session a livré tout ce qui s'était passé pendant que l'app dormait :
    /// iOS attend ce signal pour la remettre en sommeil.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
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
