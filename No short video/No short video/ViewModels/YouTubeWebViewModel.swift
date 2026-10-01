//
//  YouTubeWebViewModel.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import AVFoundation
import Combine
import WebKit

/// Central view model that owns and configures the WKWebView.
final class YouTubeWebViewModel: ObservableObject {

    // MARK: - Published State

    @Published var webViewState = WebViewState()
    @Published var showSavedFeedback: Bool = false
    @Published var showSaveError: Bool = false
    @Published var saveErrorMessage: String = ""
    @Published var sessionProgress: Double = 0.0 // 0.0 to 1.0
    @Published var isLoopEnabled: Bool = false
    @Published var isBlocked: Bool = false
    /// Site affiché — la barre d'outils s'y adapte (cf. `SiteKind`).
    @Published var currentSite: SiteKind = .youtube

    // MARK: - Properties

    let webView: WKWebView
    private let navigationDelegate: WebViewNavigationDelegate
    private let storage = VideoStorageService.shared
    private var trackingTimer: Timer?
    private var trackingTick = 0
    private var pendingSeekTime: Double?
    /// Reprendre la lecture après le seek, ou rester en pause comme avant.
    private var pendingSeekPlays = true
    private var urlObservation: NSKeyValueObservation?
    private var sessionTimer: Timer?
    private var sessionStartTime: Date?

    // MARK: - Init

    init() {
        let state = WebViewState()

        // Configure the web view
        let configuration = WKWebViewConfiguration()

        // Inject scripts
        let contentController = WKUserContentController()
        // Must run before YouTube's scripts to override the Visibility API
        contentController.addUserScript(ScriptInjectionService.backgroundAudioUserScript())
        contentController.addUserScript(ScriptInjectionService.userScript())
        // Annonces YouTube : retirées de la réponse du lecteur avant qu'il ne
        // la lise, et rattrapées dans le lecteur si l'une passe (AdSkipService).
        AdSkipService.userScripts().forEach(contentController.addUserScript)
        // Bandeaux de cookies acceptés d'office, et raccourcis SSO masqués :
        // ces flux passent par une popup ou le domaine du fournisseur, que les
        // navigateurs embarqués ne peuvent pas mener à bout.
        // Bouton « Ouvrir l'application » : l'app native est justement celle
        // qu'on évite.
        contentController.addUserScript(AppBannerService.userScript())
        contentController.addUserScript(CookieConsentService.userScript())
        contentController.addUserScript(SSOLoginService.userScript())
        #if DEBUG
        if let capture = CaptureScriptService.userScript() { contentController.addUserScript(capture) }
        #endif
        configuration.userContentController = contentController

        // Pas d'identité Safari globale ici : elle n'est posée que sur les
        // sites qui l'exigent (X), par `WebViewNavigationDelegate.userAgent`.
        // Annoncée partout, elle faisait servir la régie publicitaire de
        // YouTube — c'est ce qui a fait apparaître des annonces absentes de la
        // version publiée.

        // Media settings
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Cookie / session persistence
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // On iPhone: force mobile site. On iPad/Mac: let YouTube serve the desktop site.
        let prefs = WKWebpagePreferences()
        let isCompact = UIDevice.current.userInterfaceIdiom == .phone
        prefs.preferredContentMode = isCompact ? .mobile : .recommended
        configuration.defaultWebpagePreferences = prefs

        // Create web view (custom subclass hides keyboard accessory bar)
        let webView = NoInputAccessoryWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        // Navigation delegate
        let navDelegate = WebViewNavigationDelegate(state: state)
        webView.navigationDelegate = navDelegate

        self.webView = webView
        self.navigationDelegate = navDelegate
        self.webViewState = state

        // Bloqueur de pub : compilé une fois, appliqué au moteur avant toute
        // requête (cf. AdBlockService).
        AdBlockService.apply(to: webView)

        // Rendu tué par iOS (fréquent après un long passage en arrière-plan) :
        // on recharge en reprenant la vidéo au lieu de repartir de zéro.
        navDelegate.onWebContentProcessTerminated = { [weak self] _ in
            self?.reloadResumingPlayback(reason: "process terminated")
        }

        // Hook seek-on-load for video resume
        self.navigationDelegate.onDidFinish = { [weak self] in
            self?.currentSite = SiteKind.detect(self?.webView.url)
            self?.performPendingSeek()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.applyDynamicScripts()
                self?.checkBlockingState()
            }
        }

        // KVO: observe URL changes for SPA navigations (YouTube mobile)
        self.urlObservation = webView.observe(\.url, options: [.new]) { [weak self, weak state] webView, _ in
            DispatchQueue.main.async {
                self?.currentSite = SiteKind.detect(webView.url)
                state?.currentURL = webView.url
                state?.canGoBack = webView.canGoBack
                state?.canGoForward = webView.canGoForward
                state?.pageTitle = webView.title ?? ""

                if let url = webView.url,
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value,
                   !videoId.isEmpty {
                    state?.isOnVideoPage = true
                    state?.currentVideoId = videoId
                } else {
                    state?.isOnVideoPage = false
                    state?.currentVideoId = ""
                }

                // Re-apply dynamic scripts after SPA navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self?.applyDynamicScripts()
                    self?.checkBlockingState()
                }
            }
        }

        // `webViewState` est un objet à part : ses changements ne remontent pas
        // tout seuls à ce modèle, et la barre d'outils lit `canGoBack` /
        // `canGoForward` dessus. On les réémet ici.
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Start observing video page changes for auto-tracking
        startObservingVideoPage()

        // Start session timer
        startSessionTimer()

        // Observe UserDefaults to re-apply dynamic scripts when settings change
        observeSettings()

        // When the app is backgrounded, YouTube may still pause via its own
        // player logic. Force a play() call to counteract it.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Seulement si une vidéo jouait vraiment. Sinon on relançait le
            // premier <video> venu — un aperçu muet de l'accueil — qui volait
            // l'audio à YouTube Music ou au MP3 hors ligne et coupait la
            // musique dès le passage en arrière-plan.
            guard let self, self.wasPlayingVideo,
                  !OfflineMusicPlayer.shared.isPlaying else { return }
            self.webView.evaluateJavaScript(
                "var v=document.querySelector('video'); if(v&&v.paused) v.play();",
                completionHandler: nil
            )
        }

        // Retour au premier plan : le lecteur a parfois perdu son flux pendant
        // la suspension et tourne dans le vide. Le chien de garde est plus
        // prompt dans les secondes qui suivent (cf. `watchPlayback`).
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.foregroundReturnAt = Date()
            self.stallSeconds = 0
            self.lastProbeTime = nil
        }

        // Une autre app coupe le son (appel, pub avec du son…) : la vidéo
        // repart quand elle se tait, si elle jouait avant et que YouTube est
        // bien le compartiment affiché.
        interruptionMonitor = AudioInterruptionMonitor(
            isPlaying: { [weak self] in self?.wasPlayingVideo ?? false },
            resume: { [weak self] in
                guard let self, self.isPanelActive else { return }
                self.webView.evaluateJavaScript(
                    "var v=document.querySelector('video'); if(v&&v.paused&&!v.ended) v.play();",
                    completionHandler: nil
                )
            }
        )
    }

    deinit {
        trackingTimer?.invalidate()
        urlObservation?.invalidate()
        sessionTimer?.invalidate()
    }

    // MARK: - Navigation Actions

    func loadYouTube() {
        let request = URLRequest(url: AppConstants.youtubeURL)
        webView.load(request)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    /// Actualiser : sur une vidéo, on repart de la seconde en cours au lieu
    /// du début — `webView.reload()` rechargeait l'URL sans position.
    func reload() {
        guard webViewState.isOnVideoPage, !webViewState.currentVideoId.isEmpty else {
            webView.reload()
            return
        }
        webView.evaluateJavaScript(ScriptInjectionService.playbackProbeScript) { [weak self] result, _ in
            guard let self else { return }
            if let probe = PlaybackProbe(result), probe.hasVideo, !probe.isAd, probe.time > 0 {
                self.lastPlayback = (self.webViewState.currentVideoId, probe.time, !probe.paused)
            }
            self.reloadResumingPlayback(reason: "manual")
        }
    }

    func goHome() {
        loadYouTube()
    }

    /// Triggers Picture-in-Picture directly via the video element API.
    func triggerPiP() {
        webView.evaluateJavaScript("""
            (function(){
                var v = document.querySelector('video');
                if (!v) return;
                if (document.pictureInPictureElement) {
                    document.exitPictureInPicture().catch(function(){});
                } else if ('requestPictureInPicture' in v) {
                    v.requestPictureInPicture().catch(function(){});
                }
            })();
            """, completionHandler: nil)
    }

    /// Loads any URL directly (used by the browser home favourites).
    func loadURL(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Ce compartiment est-il celui qu'on regarde ?
    ///
    /// Piloté par ContentView. Quand il est faux, la vidéo est en pause et doit
    /// le rester : les deux rattrapages qui relancent la lecture (retour
    /// d'arrière-plan, fin d'appel téléphonique) les ignorent, sans quoi
    /// YouTube se remettait à jouer par-dessus YouTube Music.
    private(set) var isPanelActive = true

    func setPanelActive(_ active: Bool) {
        isPanelActive = active
        if !active { pauseMedia() }
    }

    /// Coupe la lecture en cours.
    ///
    /// Appelé quand on quitte le compartiment YouTube — pour la musique ou pour
    /// un autre site. `backgroundAudioScript` fait croire à YouTube que la page
    /// est toujours visible, ce qui est exactement ce qu'on veut quand l'app
    /// passe en arrière-plan, et exactement ce qu'on ne veut pas quand on part
    /// ailleurs dans l'app : sans cet appel, la vidéo continuait de jouer sous
    /// YouTube Music.
    func pauseMedia() {
        webView.evaluateJavaScript(ScriptInjectionService.pauseAllMediaScript,
                                   completionHandler: nil)
    }
    
    /// Performs a YouTube search with the given query.
    func search(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURLString = "https://m.youtube.com/results?search_query=\(encodedQuery)"
        if let url = URL(string: searchURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    /// Adds or removes the bottom padding on the page depending on toolbar visibility.
    func setBottomMargin(visible: Bool) {
        let px = visible ? "60px" : "0px"
        webView.evaluateJavaScript("document.body.style.paddingBottom = '\(px)';", completionHandler: nil)
    }

    // MARK: - Video Save (Always Enabled)

    /// Saves the current page. Tries JS extraction first, then falls back to URL parsing.
    func saveCurrentVideo() {
        // Strategy A: JS extraction (multiple strategies inside the script)
        webView.evaluateJavaScript(ScriptInjectionService.videoInfoScript) { [weak self] result, error in
            guard let self = self else { return }

            var videoId: String?
            var title = "Untitled"
            var currentTime: Double = 0
            var duration: Double = 0

            // Parse JS result
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let jsVideoId = info["videoId"] as? String ?? ""
                if !jsVideoId.isEmpty {
                    videoId = jsVideoId
                }
                title = info["title"] as? String ?? "Untitled"
                currentTime = info["currentTime"] as? Double ?? 0
                duration = info["duration"] as? Double ?? 0
            }

            // Strategy B: parse webView.url directly (Swift-side)
            if videoId == nil || videoId!.isEmpty {
                videoId = self.extractVideoIdFromSwift()
            }

            // Strategy C: parse the raw href returned by JS
            if videoId == nil || videoId!.isEmpty,
               let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawURL = info["url"] as? String {
                videoId = self.extractVideoId(from: rawURL)
            }

            // If we found a video ID, save it
            if let vid = videoId, !vid.isEmpty {
                if title.isEmpty || title == "Untitled" || title == "YouTube" {
                    title = "Video \(vid)"
                }

                let video = SavedVideo(
                    id: vid,
                    title: title,
                    thumbnailURL: SavedVideo.thumbnailURL(for: vid),
                    url: "https://m.youtube.com/watch?v=\(vid)",
                    lastTime: currentTime,
                    duration: duration,
                    dateAdded: Date()
                )

                self.storage.save(video)

                DispatchQueue.main.async {
                    self.showSavedFeedback = true
                    ReviewPromptService.shared.recordSuccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.showSavedFeedback = false
                    }
                }
            } else {
                // All strategies failed — show error popup
                DispatchQueue.main.async {
                    self.saveErrorMessage = "Could not detect a video on this page.\n\nMake sure you are on a YouTube video page (not the home feed).\n\nCurrent URL: \(self.webView.url?.absoluteString ?? "unknown")"
                    self.showSaveError = true
                }
            }
        }
    }

    // MARK: - Offline Download

    /// Lance le téléchargement hors ligne de la vidéo à l'écran. Tout se passe
    /// en coulisse (cf. `VideoDownloadService`) : on ne fait ici qu'identifier
    /// la vidéo, avec les mêmes stratégies que le favori.
    func downloadCurrentVideo() {
        webView.evaluateJavaScript(ScriptInjectionService.videoInfoScript) { [weak self] result, _ in
            guard let self else { return }

            var info: [String: Any] = [:]
            if let json = result as? String, let data = json.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                info = parsed
            }

            var videoId = info["videoId"] as? String ?? ""
            if videoId.isEmpty { videoId = self.extractVideoIdFromSwift() ?? "" }
            if videoId.isEmpty, let raw = info["url"] as? String { videoId = self.extractVideoId(from: raw) ?? "" }

            guard !videoId.isEmpty else {
                self.saveErrorMessage = UserDefaults.standard.string(forKey: "appLanguage") == "fr"
                    ? "Ouvrez une vidéo YouTube pour la télécharger."
                    : "Open a YouTube video to download it."
                self.showSaveError = true
                return
            }

            var title = info["title"] as? String ?? ""
            if title.isEmpty || title == "YouTube" { title = "Video \(videoId)" }
            VideoDownloadService.shared.start(
                videoId: videoId,
                title: title,
                duration: info["duration"] as? Double ?? 0
            )
        }
    }

    // MARK: - Swift-side Video ID Extraction

    /// Extracts video ID from the current webView URL using Swift.
    private func extractVideoIdFromSwift() -> String? {
        guard let url = webView.url else { return nil }
        return extractVideoId(from: url.absoluteString)
    }

    /// Extracts a YouTube video ID from any URL string.
    private func extractVideoId(from urlString: String) -> String? {
        // Pattern 1: ?v=XXXXXXXXXXX
        if let range = urlString.range(of: "[?&]v=([a-zA-Z0-9_-]{11})", options: .regularExpression) {
            let match = urlString[range]
            let id = match.dropFirst(3) // drop ?v= or &v=
            return String(id)
        }

        // Pattern 2: youtu.be/XXXXXXXXXXX
        if let range = urlString.range(of: "youtu\\.be/([a-zA-Z0-9_-]{11})", options: .regularExpression) {
            let match = urlString[range]
            let parts = match.split(separator: "/")
            if parts.count >= 2 { return String(parts[1]) }
        }

        // Pattern 3: /embed/XXXXXXXXXXX
        if let range = urlString.range(of: "/embed/([a-zA-Z0-9_-]{11})", options: .regularExpression) {
            let match = urlString[range]
            let parts = match.split(separator: "/")
            if let last = parts.last { return String(last) }
        }

        return nil
    }

    // MARK: - Resume

    /// Opens a saved video and seeks to the stored timestamp.
    func openVideo(_ video: SavedVideo) {
        pendingSeekTime = video.lastTime
        if let url = URL(string: video.url) {
            webView.load(URLRequest(url: url))
        }
    }

    /// Called by the navigation delegate after page load to perform pending seek.
    func performPendingSeek() {
        guard let seekTime = pendingSeekTime, seekTime > 0 else { return }
        pendingSeekTime = nil
        let plays = pendingSeekPlays
        pendingSeekPlays = true

        // Le script attend lui-même que le lecteur soit monté : inutile de
        // patienter ici plus que le temps que YouTube démarre son JS.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.webView.evaluateJavaScript(
                ScriptInjectionService.resumeScript(to: seekTime, play: plays),
                completionHandler: nil
            )
            // Restore loop state on the new video
            if self.isLoopEnabled {
                self.webView.evaluateJavaScript(
                    ScriptInjectionService.loopScript(enabled: true),
                    completionHandler: nil
                )
            }
        }
    }

    // MARK: - Loop

    func toggleLoop() {
        isLoopEnabled.toggle()
        webView.evaluateJavaScript(
            ScriptInjectionService.loopScript(enabled: isLoopEnabled),
            completionHandler: nil
        )
    }

    // MARK: - Auto Tracking

    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Session Timer
    
    private func startSessionTimer() {
        sessionStartTime = Date()
        sessionProgress = 0.0
        
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSessionProgress()
        }
    }
    
    private var currentDailyLimitSeconds: Double {
        let minutes = UserDefaults.standard.integer(forKey: "dailyLimitMinutes")
        return Double(minutes > 0 ? minutes : 60) * 60
    }

    private func updateSessionProgress() {
        guard let startTime = sessionStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        sessionProgress = min(1.0, elapsed / currentDailyLimitSeconds)
        checkBlockingState()

        // Count one second of app usage only while actually on screen.
        if UIApplication.shared.applicationState == .active {
            DailyStatsStore.shared.tick()
        }
    }

    // MARK: - Dynamic Settings Scripts

    private func observeSettings() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyDynamicScripts()
            self?.checkBlockingState()
        }
    }

    func applyDynamicScripts() {
        let hideRecs   = UserDefaults.standard.bool(forKey: "hideRecommendations")
        let blurThumbs = UserDefaults.standard.bool(forKey: "blurThumbnails")
        let grayscale  = UserDefaults.standard.bool(forKey: "grayscaleMode")

        let recsScript = hideRecs
            ? ScriptInjectionService.hideRecommendationsScript
            : ScriptInjectionService.showRecommendationsScript
        let blurScript = blurThumbs
            ? ScriptInjectionService.blurThumbnailsScript
            : ScriptInjectionService.removeBlurThumbnailsScript
        let grayScript = grayscale
            ? ScriptInjectionService.grayscaleScript
            : ScriptInjectionService.removeGrayscaleScript

        webView.evaluateJavaScript(recsScript, completionHandler: nil)
        webView.evaluateJavaScript(blurScript, completionHandler: nil)
        webView.evaluateJavaScript(grayScript, completionHandler: nil)

        // Le bloqueur s'ajoute et se retire à chaud : pas besoin de recharger.
        AdBlockService.apply(to: webView)
    }

    func checkBlockingState() {
        let blockOnLimit = UserDefaults.standard.bool(forKey: "blockOnLimit")
        let shouldBlock  = blockOnLimit && sessionProgress >= 1.0
        if isBlocked != shouldBlock {
            isBlocked = shouldBlock
        }
    }

    private func startObservingVideoPage() {
        webViewState.$isOnVideoPage
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnVideo in
                if isOnVideo {
                    self?.startTracking()
                } else {
                    self?.stopTracking()
                }
            }
            .store(in: &cancellables)

        // Count each distinct video opened towards today's watch total.
        webViewState.$currentVideoId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { id in
                DailyStatsStore.shared.recordVideoWatched(id: id)
            }
            .store(in: &cancellables)
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        stallSeconds = 0
        lastProbeTime = nil
        trackingTick = 0
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.watchPlayback()
            // La bibliothèque n'a pas besoin de la seconde près : on n'y écrit
            // qu'une fois sur cinq.
            self.trackingTick += 1
            if self.trackingTick % 5 == 0 { self.trackProgress() }
        }
    }

    private func stopTracking() {
        trackProgress()
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func trackProgress() {
        guard webViewState.isOnVideoPage, !webViewState.currentVideoId.isEmpty else { return }

        webView.evaluateJavaScript(ScriptInjectionService.videoInfoScript) { [weak self] result, error in
            guard let self = self,
                  let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            let videoId = info["videoId"] as? String ?? self.extractVideoIdFromSwift() ?? ""
            let currentTime = info["currentTime"] as? Double ?? 0
            let duration = info["duration"] as? Double ?? 0

            guard !videoId.isEmpty, currentTime > 0 else { return }

            let existing = self.storage.loadAll()
            if var video = existing.first(where: { $0.id == videoId }) {
                video.lastTime = currentTime
                if duration > 0 { video.duration = duration }
                self.storage.save(video)
            }
        }
    }

    // MARK: - Chien de garde de lecture

    /// Dernière position vue en lecture normale (hors pub) : c'est là qu'on
    /// reprend après un rechargement.
    private var lastPlayback: (videoId: String, time: Double, playing: Bool)?

    /// La vidéo de la page jouait au dernier relevé, dans le compartiment
    /// affiché : c'est la seule qu'on a le droit de relancer.
    private var wasPlayingVideo: Bool {
        guard isPanelActive, webViewState.isOnVideoPage,
              let snap = lastPlayback,
              snap.videoId == webViewState.currentVideoId
        else { return false }
        return snap.playing
    }
    private var interruptionMonitor: AudioInterruptionMonitor?
    private var lastProbeTime: Double?
    /// Secondes consécutives où le lecteur devait avancer et n'a pas bougé.
    private var stallSeconds = 0
    private var foregroundReturnAt: Date?
    private var lastAutoReloadAt: Date?
    /// Rechargements automatiques d'affilée sans que la lecture reparte —
    /// au-delà, on laisse la main : recharger ne résout pas un réseau mort.
    private var autoReloadStreak = 0

    /// Juste après un retour au premier plan, une roue qui tourne est presque
    /// toujours un flux perdu pendant la suspension : on réagit vite. Le reste
    /// du temps ce peut être un vrai buffering réseau, on laisse plus de marge.
    private static let stallLimitAfterForeground = 4
    private static let stallLimit = 10
    private static let foregroundWindow: TimeInterval = 20
    private static let autoReloadCooldown: TimeInterval = 15
    private static let maxAutoReloadStreak = 3

    private struct PlaybackProbe {
        let hasVideo: Bool
        let time: Double
        let paused: Bool
        let ended: Bool
        let readyState: Int
        let isAd: Bool

        init?(_ result: Any?) {
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            hasVideo   = info["has"] as? Bool ?? false
            time       = info["t"] as? Double ?? 0
            paused     = info["paused"] as? Bool ?? true
            ended      = info["ended"] as? Bool ?? false
            readyState = info["rs"] as? Int ?? 0
            isAd       = info["ad"] as? Bool ?? false
        }
    }

    /// Relevé chaque seconde sur une page vidéo : mémorise la position, et
    /// recharge en reprenant à cette position si le lecteur reste bloqué.
    private func watchPlayback() {
        let videoId = webViewState.currentVideoId
        guard webViewState.isOnVideoPage, !videoId.isEmpty else { return }

        webView.evaluateJavaScript(ScriptInjectionService.playbackProbeScript) { [weak self] result, error in
            guard let self, self.webViewState.currentVideoId == videoId else { return }
            let probe = PlaybackProbe(result)

            if let probe, probe.hasVideo, !probe.isAd {
                let advanced = self.lastProbeTime.map { abs(probe.time - $0) > 0.2 } ?? false
                self.lastProbeTime = probe.time
                if probe.time > 0 {
                    self.lastPlayback = (videoId, probe.time, !probe.paused)
                }
                if advanced {
                    self.stallSeconds = 0
                    self.autoReloadStreak = 0
                    return
                }
            }

            // En arrière-plan, pendant un chargement ou quand YouTube n'est pas
            // à l'écran, on se contente de noter la position.
            guard UIApplication.shared.applicationState == .active,
                  self.isPanelActive, !self.isBlocked,
                  !self.webViewState.isLoading
            else { self.stallSeconds = 0; return }

            let justReturned = self.foregroundReturnAt.map {
                Date().timeIntervalSince($0) < Self.foregroundWindow
            } ?? false

            if self.isStalled(probe, error: error, justReturned: justReturned) {
                self.stallSeconds += 1
            } else {
                self.stallSeconds = 0
            }

            let limit = justReturned ? Self.stallLimitAfterForeground : Self.stallLimit
            guard self.stallSeconds >= limit,
                  self.autoReloadStreak < Self.maxAutoReloadStreak,
                  self.lastAutoReloadAt.map({ Date().timeIntervalSince($0) > Self.autoReloadCooldown }) ?? true
            else { return }

            self.autoReloadStreak += 1
            self.lastAutoReloadAt = Date()
            self.reloadResumingPlayback(reason: "stalled \(self.stallSeconds)s")
        }
    }

    /// Le lecteur devrait avancer et n'avance pas.
    private func isStalled(_ probe: PlaybackProbe?, error: Error?, justReturned: Bool) -> Bool {
        // Le JS ne répond plus : le rendu est figé.
        guard let probe else { return error != nil || justReturned }
        if probe.isAd || probe.ended { return false }
        // Page vidéo sans lecteur : il a été démonté pendant la suspension.
        guard probe.hasVideo else { return justReturned }
        // Lecture demandée mais rien en mémoire tampon : la roue qui tourne.
        if !probe.paused { return probe.readyState < 3 }
        // En pause avec un lecteur vidé (flux perdu) : seulement juste après
        // un retour, sinon c'est une pause voulue.
        return justReturned && probe.readyState == 0 && (lastPlayback?.playing ?? false)
    }

    /// Recharge la page vidéo et reprend à la dernière position connue.
    ///
    /// La position part aussi dans l'URL (`t=`), que YouTube applique de
    /// lui-même dès le chargement ; `resumeScript` affine à la seconde près.
    private func reloadResumingPlayback(reason: String) {
        let videoId = webViewState.currentVideoId
        guard let url = webView.url ?? webViewState.currentURL else {
            webView.reload()
            return
        }
        guard !videoId.isEmpty,
              let snap = lastPlayback, snap.videoId == videoId, snap.time > 1,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            webView.load(URLRequest(url: url))
            return
        }

        var items = (components.queryItems ?? []).filter { $0.name != "t" && $0.name != "start" }
        items.append(URLQueryItem(name: "t", value: "\(Int(snap.time))s"))
        components.queryItems = items

        #if DEBUG
        print("[Playback] reload (\(reason)) → \(videoId) @ \(Int(snap.time))s")
        #endif

        pendingSeekTime = snap.time
        pendingSeekPlays = snap.playing
        stallSeconds = 0
        lastProbeTime = nil
        webView.load(URLRequest(url: components.url ?? url))
    }
}
