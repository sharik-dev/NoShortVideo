//
//  MusicWebViewModel.swift
//  No short video
//

import Combine
import WebKit

/// YouTube Music tourne dans **sa propre WKWebView**, séparée de celle qui sert
/// à naviguer.
///
/// C'est la seule façon d'obtenir ce qu'on veut : une seule webview, c'est une
/// seule page, et charger Instagram par-dessus YouTube Music coupe le son. Ici
/// la webview musicale reste montée en permanence (masquée par-dessous quand on
/// navigue ailleurs, jamais retirée de la hiérarchie — WebKit couperait la
/// lecture), pendant que la webview principale va où elle veut.
///
/// Deux règles portées par ce modèle :
/// - la musique **survit** à la navigation vers Instagram, X, LinkedIn… ;
/// - elle **s'arrête** dès qu'une vidéo YouTube démarre dans l'autre webview,
///   parce que deux sons en même temps n'ont aucun sens (cf. `pauseForVideo`).
final class MusicWebViewModel: ObservableObject {

    /// Une session musicale existe — la webview a été chargée au moins une fois
    /// et n'a pas été abandonnée. Pilote l'affichage de la bannière.
    @Published private(set) var hasSession: Bool = false
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var trackTitle: String = ""
    @Published private(set) var artist: String = ""
    /// Confirmation « morceau enregistré », affichée par ContentView.
    @Published var showSavedFeedback: Bool = false
    /// Message quand l'enregistrement n'a pas pu se faire (rien en lecture).
    @Published var saveErrorMessage: String?

    private let storage = VideoStorageService.music
    private var pendingSeekTime: Double?

    let webView: WKWebView

    private var pollTimer: Timer?
    private var interruptionMonitor: AudioInterruptionMonitor?
    private static let homeURL = URL(string: "https://music.youtube.com")!

    // MARK: - Init

    init() {
        let contentController = WKUserContentController()
        // Même parade que la webview principale : sans elle, YouTube Music met
        // la lecture en pause dès que la page n'est plus au premier plan.
        contentController.addUserScript(ScriptInjectionService.backgroundAudioUserScript())
        // Les annonces entre deux morceaux : retirées de la réponse du lecteur
        // avant qu'il ne la lise, faute de pouvoir les bloquer au réseau
        // (cf. AdSkipService).
        AdSkipService.userScripts().forEach(contentController.addUserScript)
        // Même traitement que la webview principale : YouTube Music affiche lui
        // aussi un bandeau de consentement.
        // Bouton « Ouvrir l'application » : l'app native est justement celle
        // qu'on évite.
        contentController.addUserScript(AppBannerService.userScript())
        contentController.addUserScript(CookieConsentService.userScript())
        #if DEBUG
        if let capture = CaptureScriptService.userScript() { contentController.addUserScript(capture) }
        #endif

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        // Surtout pas d'UA Safari ici : c'est lui qui faisait servir des
        // annonces entre les morceaux (voir YouTubeWebViewModel).
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Même pot de cookies que la webview principale : la session Google est
        // déjà là, on ne redemande pas de se connecter.
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode = UIDevice.current.userInterfaceIdiom == .phone ? .mobile : .recommended
        configuration.defaultWebpagePreferences = prefs

        webView = NoInputAccessoryWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Pas de bloqueur de pub ici, volontairement.
        //
        // Il n'apportait rien — les annonces de YouTube Music sont servies par
        // `googlevideo.com`, le domaine qui sert aussi la musique, donc
        // impossible à bloquer sans couper la lecture — et il coûtait cher :
        // écran noir au lancement de la session musicale. Cette webview reste
        // exactement telle qu'elle était.

        // Une pub dans une autre app coupe le morceau : il repart dès qu'elle
        // se tait. `isPlaying` date du dernier relevé (2 s), donc d'avant la
        // coupure — c'est justement l'état qu'on veut retrouver.
        interruptionMonitor = AudioInterruptionMonitor(
            isPlaying: { [weak self] in
                guard let self else { return false }
                return self.hasSession && !self.isSuspended && self.isPlaying
            },
            resume: { [weak self] in
                guard let self, self.hasSession, !self.isSuspended else { return }
                self.webView.evaluateJavaScript(Self.resumeIfPausedJS) { [weak self] _, _ in
                    self?.refreshState()
                }
            }
        )
        observeBackground()
    }

    deinit {
        pollTimer?.invalidate()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    private var backgroundObserver: NSObjectProtocol?

    /// WebKit met la vidéo en pause au passage en arrière-plan, masquer la
    /// visibilité de la page (`backgroundAudioScript`) n'y change rien. Si un
    /// morceau jouait, on le relance aussitôt — plusieurs fois, la première
    /// tentative arrive parfois avant la pause. Sans effet sur un lecteur qui
    /// joue déjà.
    private func observeBackground() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.hasSession, !self.isSuspended, self.isPlaying,
                  !OfflineMusicPlayer.shared.isPlaying else { return }
            for delay in [0, 0.5, 1.5] as [TimeInterval] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.hasSession, !self.isSuspended else { return }
                    self.webView.evaluateJavaScript(Self.resumeIfPausedJS) { [weak self] _, _ in
                        self?.refreshState()
                    }
                }
            }
        }
    }

    // MARK: - Session

    /// Ouvre YouTube Music, ou revient dessus si une session tourne déjà —
    /// recharger couperait le morceau en cours.
    func openMusic() {
        if isSuspended { resume(); return }
        if !hasSession {
            webView.load(URLRequest(url: Self.homeURL))
            hasSession = true
            startPolling()
        }
    }

    // MARK: - Veille

    /// La page musicale est déchargée, mais la session existe toujours : le
    /// bandeau reste, et on sait où reprendre.
    @Published private(set) var isSuspended: Bool = false

    private var suspendedURL: URL?
    private var suspendedTime: Double = 0

    /// Met la webview musicale en veille **si rien ne joue**.
    ///
    /// Sans ça, YouTube Music restait chargé et connecté en arrière-plan tout
    /// le temps qu'on passait sur YouTube — deux pages Google authentifiées et
    /// actives sur le même compte, dont une qui ment sur sa visibilité
    /// (`backgroundAudioScript`). Il n'y a aucune raison de la laisser tourner
    /// là : sur une page vidéo YouTube, la musique est de toute façon mise en
    /// pause par `pauseForVideo`.
    ///
    /// La lecture en cours est sacrée : si un morceau joue, on ne touche à
    /// rien. C'est toute la promesse de la webview séparée.
    func suspendIfIdle() {
        guard hasSession, !isSuspended, !isPlaying else { return }

        let url = webView.url
        webView.evaluateJavaScript(Self.positionJS) { [weak self] result, _ in
            guard let self, !self.isPlaying else { return }
            self.suspendedTime = (result as? Double) ?? 0
            self.suspendedURL  = url
            self.stopPolling()
            // Page vide : plus de requêtes, plus de timers, plus de session
            // active côté Google.
            self.webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            self.isSuspended = true
        }
    }

    /// Recharge la page musicale là où la veille l'avait laissée.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false

        guard let url = suspendedURL else {
            hasSession = false      // rien à reprendre : on repart de l'accueil
            openMusic()
            return
        }

        webView.load(URLRequest(url: url))
        startPolling()

        // YouTube Music monte son lecteur bien après le didFinish de la page.
        let seek = suspendedTime
        guard seek > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.webView.evaluateJavaScript(ScriptInjectionService.seekScript(to: seek),
                                             completionHandler: nil)
        }
    }

    /// Abandonne la session : la lecture s'arrête et la bannière disparaît.
    func discard() {
        isSuspended = false
        suspendedURL = nil
        suspendedTime = 0
        stopPolling()
        webView.stopLoading()
        webView.evaluateJavaScript(Self.pauseJS, completionHandler: nil)
        // Page blanche : la webview reste montée mais ne joue plus rien et ne
        // garde pas le morceau en mémoire.
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        hasSession = false
        isPlaying = false
        trackTitle = ""
        artist = ""
    }

    // MARK: - Favori

    /// Enregistre le morceau en cours dans la bibliothèque musicale.
    ///
    /// On n'enregistre que ce qui **joue** : sur une page de recherche ou une
    /// playlist qu'on n'a pas lancée, il n'y a pas de lien de morceau à garder,
    /// et enregistrer l'URL de la page ne servirait à rien.
    func saveCurrentTrack() {
        guard hasSession else { return }

        webView.evaluateJavaScript(Self.trackInfoJS) { [weak self] result, _ in
            guard let self else { return }

            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let videoId = info["videoId"] as? String, !videoId.isEmpty
            else {
                DispatchQueue.main.async {
                    self.saveErrorMessage = "Lance un morceau avant de l'enregistrer."
                }
                return
            }

            let title = (info["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            let artist = info["artist"] as? String ?? ""

            let track = SavedVideo(
                id: videoId,
                title: artist.isEmpty ? title : "\(title) — \(artist)",
                thumbnailURL: SavedVideo.thumbnailURL(for: videoId),
                url: "https://music.youtube.com/watch?v=\(videoId)",
                lastTime: info["currentTime"] as? Double ?? 0,
                duration: info["duration"] as? Double ?? 0,
                dateAdded: Date()
            )
            self.storage.save(track)

            DispatchQueue.main.async {
                // Téléchargé en MP3 dans cinq minutes, en silence.
                VideoDownloadService.shared.downloadDueFavorites()
                self.showSavedFeedback = true
                ReviewPromptService.shared.recordSuccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    self.showSavedFeedback = false
                }
            }
        }
    }

    /// Télécharge le morceau en cours en MP3 pour l'écouter hors ligne (cf.
    /// `VideoDownloadService`). Contrairement au favori, il n'a pas besoin
    /// d'être en lecture : un morceau en pause s'enregistre aussi bien.
    func downloadCurrentTrack() {
        guard hasSession else { return }
        webView.evaluateJavaScript(Self.downloadInfoJS) { [weak self] result, _ in
            guard let self else { return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let videoId = info["videoId"] as? String, !videoId.isEmpty
            else {
                self.saveErrorMessage = UserDefaults.standard.string(forKey: "appLanguage") == "fr"
                    ? "Lance un morceau avant de le télécharger."
                    : "Play a track before downloading it."
                return
            }
            let title = (info["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            let artist = info["artist"] as? String ?? ""
            VideoDownloadService.shared.start(
                videoId: videoId,
                title: artist.isEmpty ? title : "\(title) — \(artist)",
                duration: info["duration"] as? Double ?? 0,
                format: .mp3
            )
        }
    }

    /// Comme `trackInfoJS`, sans exiger que le morceau joue.
    private static let downloadInfoJS = """
    (function() {
        var v = document.querySelector('video');
        var videoId = '';
        try { videoId = new URLSearchParams(location.search).get('v') || ''; } catch (e) {}
        var title = '', artist = '';
        try {
            var meta = navigator.mediaSession && navigator.mediaSession.metadata;
            if (meta) { title = meta.title || ''; artist = meta.artist || ''; }
        } catch (e) {}
        if (!title) title = (document.title || '').replace(' - YouTube Music', '');
        return JSON.stringify({
            videoId: videoId, title: title, artist: artist,
            duration: v && isFinite(v.duration) ? v.duration : 0
        });
    })();
    """

    /// Rouvre un morceau de la bibliothèque, à l'endroit où il avait été laissé.
    func openTrack(_ track: SavedVideo) {
        guard let url = URL(string: track.url) else { return }
        isSuspended = false     // on recharge une vraie page : la veille est levée
        pendingSeekTime = track.lastTime
        webView.load(URLRequest(url: url))
        if !hasSession {
            hasSession = true
            startPolling()
        }
        // YouTube Music monte son lecteur bien après le didFinish de la page.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, let seek = self.pendingSeekTime, seek > 0 else { return }
            self.pendingSeekTime = nil
            self.webView.evaluateJavaScript(ScriptInjectionService.seekScript(to: seek),
                                            completionHandler: nil)
        }
    }

    // MARK: - Navigation

    // Exposées ici plutôt que d'ouvrir la WKWebView à la barre d'outils : une
    // vue SwiftUI n'a pas à importer WebKit pour appuyer sur « retour ».
    #if DEBUG
    /// Captures de l'onboarding : ouvrir un morceau précis (`-debugOpenURL`).
    func debugLoad(_ url: URL) { webView.load(URLRequest(url: url)) }
    #endif

    func goBack()    { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload()    { webView.reload() }

    // MARK: - Lecture

    func togglePlayPause() {
        guard hasSession else { return }

        // En veille, la page est vide : on la recharge, puis on lance la
        // lecture une fois le lecteur monté.
        if isSuspended {
            resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
                self?.webView.evaluateJavaScript(Self.playJS) { _, _ in
                    self?.refreshState()
                }
            }
            return
        }

        if isPlaying { interruptionMonitor?.cancelPendingResume() }
        webView.evaluateJavaScript(isPlaying ? Self.pauseJS : Self.playJS) { [weak self] _, _ in
            self?.refreshState()
        }
    }

    /// Appelé quand une vidéo YouTube démarre dans la webview principale.
    /// On met en pause sans abandonner la session : la bannière reste, et un
    /// appui sur lecture reprend le morceau où il en était.
    func pauseForVideo() {
        // La vidéo a pris la place : la fin d'une coupure ne doit pas relancer
        // la musique par-dessus.
        interruptionMonitor?.cancelPendingResume()
        guard hasSession, isPlaying else { return }
        webView.evaluateJavaScript(Self.pauseJS) { [weak self] _, _ in
            self?.refreshState()
        }
    }

    // MARK: - État

    private func startPolling() {
        stopPolling()
        refreshState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshState() {
        guard hasSession else { return }
        webView.evaluateJavaScript(Self.stateJS) { [weak self] result, _ in
            guard let self, let json = result as? String,
                  let data = json.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            self.isPlaying  = info["playing"] as? Bool ?? false
            self.trackTitle = info["title"]   as? String ?? ""
            self.artist     = info["artist"]  as? String ?? ""
        }
    }

    // MARK: - Scripts

    /// Position de lecture, y compris à l'arrêt — `trackInfoJS` ne répond rien
    /// quand rien ne joue, or c'est exactement le cas où l'on met en veille.
    private static let positionJS = """
    (function() {
        var v = document.querySelector('video');
        return (v && isFinite(v.currentTime)) ? v.currentTime : 0;
    })();
    """

    private static let playJS  = "var v=document.querySelector('video'); if(v) v.play();"
    private static let pauseJS = "var v=document.querySelector('video'); if(v) v.pause();"
    /// Sans effet si ça joue déjà : les relances après coupure peuvent s'empiler.
    private static let resumeIfPausedJS =
        "var v=document.querySelector('video'); if(v&&v.paused&&!v.ended){var r=v.play(); if(r&&r.catch) r.catch(function(){});}"

    /// Tout ce qu'il faut pour enregistrer un morceau. L'identifiant vient de
    /// l'URL `watch?v=`, la seule source fiable sur YouTube Music.
    static let trackInfoJS = """
    (function() {
        var v = document.querySelector('video');
        if (!v || v.paused || v.ended) return '';

        var videoId = '';
        try {
            videoId = new URLSearchParams(location.search).get('v') || '';
        } catch (e) {}

        var title = '', artist = '';
        try {
            var meta = navigator.mediaSession && navigator.mediaSession.metadata;
            if (meta) { title = meta.title || ''; artist = meta.artist || ''; }
        } catch (e) {}
        if (!title) title = (document.title || '').replace(' - YouTube Music', '');

        return JSON.stringify({
            videoId: videoId,
            title: title,
            artist: artist,
            currentTime: v.currentTime || 0,
            duration: isFinite(v.duration) ? v.duration : 0
        });
    })();
    """

    /// Titre et interprète viennent de `mediaSession`, que YouTube Music
    /// renseigne pour l'écran verrouillé — c'est la source la plus propre.
    private static let stateJS = """
    (function() {
        var v = document.querySelector('video');
        var title = '', artist = '';
        try {
            var meta = navigator.mediaSession && navigator.mediaSession.metadata;
            if (meta) { title = meta.title || ''; artist = meta.artist || ''; }
        } catch (e) {}
        if (!title) title = (document.title || '').replace(' - YouTube Music', '');
        return JSON.stringify({
            playing: !!(v && !v.paused && !v.ended),
            title: title,
            artist: artist
        });
    })();
    """
}
