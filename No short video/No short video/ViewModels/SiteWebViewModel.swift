//
//  SiteWebViewModel.swift
//  No short video
//

import Combine
import WebKit

/// Une webview **par raccourci** : Twitch, Instagram, LinkedIn, X, et une pour
/// tout le reste (recherche, URL tapée à la main).
///
/// Avant, une seule webview servait tout le monde. Ouvrir Instagram alors qu'on
/// était sur X, c'était charger une page par-dessus l'autre : on voyait X
/// pendant toute la durée du chargement — la demi-seconde de trop — et la vidéo
/// qui jouait sur X continuait jusqu'à ce que sa page soit remplacée. Ici
/// chaque site garde sa page, son historique et sa session : y revenir est
/// instantané et montre exactement ce qu'on avait laissé, jamais le site
/// précédent.
///
/// Corollaire volontaire : **une webview qui passe à l'arrière-plan se tait**
/// (cf. `pauseMedia`). C'est ContentView qui l'appelle au moment de changer de
/// compartiment.
final class SiteWebViewModel: ObservableObject {

    let site: SiteKind
    let webView: WKWebView
    let state = WebViewState()

    /// Une page a déjà été demandée — la webview n'est plus vierge.
    @Published private(set) var hasContent = false
    /// La première page est arrivée à l'écran. Tant que c'est faux, ContentView
    /// couvre la webview : sans ça, on verrait son blanc au premier affichage.
    @Published private(set) var isReady = false

    private let navigationDelegate: WebViewNavigationDelegate
    private var cancellables = Set<AnyCancellable>()

    /// L'adresse d'origine du raccourci — c'est là que « recharger » ramène
    /// quand la page a été perdue.
    private(set) var homeURL: URL?

    // MARK: - Init

    init(site: SiteKind) {
        self.site = site

        let contentController = WKUserContentController()
        // Même parade que la webview YouTube : sans elle, une vidéo se met en
        // pause dès que la page n'est plus au premier plan.
        contentController.addUserScript(ScriptInjectionService.backgroundAudioUserScript())
        // Vidéos courtes des réseaux sociaux — la promesse de l'app.
        contentController.addUserScript(SocialShortsService.userScript())
        // Bandeaux « ouvre l'app », consentement cookies, raccourcis SSO qui ne
        // peuvent pas aboutir dans un navigateur embarqué.
        contentController.addUserScript(AppBannerService.userScript())
        contentController.addUserScript(CookieConsentService.userScript())
        contentController.addUserScript(SSOLoginService.userScript())
        // La musique passe avant les vidéos du fil (cf. MusicPriorityService).
        contentController.addUserScript(MusicPriorityService.userScript())
        if UIDevice.current.userInterfaceIdiom == .phone {
            contentController.addUserScript(
                WKUserScript(source: ScriptInjectionService.bottomMarginScript,
                             injectionTime: .atDocumentEnd,
                             forMainFrameOnly: false)
            )
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Même pot de cookies que les autres webviews : les sessions déjà
        // ouvertes le restent.
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode =
            UIDevice.current.userInterfaceIdiom == .phone ? .mobile : .recommended
        configuration.defaultWebpagePreferences = prefs

        let webView = NoInputAccessoryWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        let navDelegate = WebViewNavigationDelegate(state: state)
        webView.navigationDelegate = navDelegate
        self.navigationDelegate = navDelegate

        AdBlockService.apply(to: webView)

        navDelegate.onDidFinish = { [weak self] in
            guard let self else { return }
            self.isReady = true
            // Page neuve : le script repart muet par défaut, on lui redit
            // si la musique joue.
            if self.mutesForMusic { self.applyMusicMute() }
        }

        // La barre d'outils lit `canGoBack` / `canGoForward` depuis l'état :
        // il faut donc que ce modèle se signale quand l'état change.
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    /// Ouvre le raccourci. Une page déjà chargée n'est **pas** rechargée : on
    /// la retrouve où on l'avait laissée, c'est tout l'intérêt du compartiment.
    func open(_ url: URL) {
        if homeURL == nil { homeURL = url }
        guard !hasContent else { return }
        hasContent = true
        webView.load(URLRequest(url: url))
    }

    /// Force le chargement d'une adresse précise dans ce compartiment, même
    /// s'il en affiche déjà une (recherche, URL tapée à la main).
    func load(_ url: URL) {
        if homeURL == nil { homeURL = url }
        hasContent = true
        isReady = false
        webView.load(URLRequest(url: url))
    }

    func goBack()    { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        if webView.url == nil, let homeURL {
            webView.load(URLRequest(url: homeURL))
        } else {
            webView.reload()
        }
    }

    // MARK: - Son

    /// Coupe tout ce qui joue dans ce compartiment. Appelé au moment d'en
    /// sortir : une page qu'on ne voit plus n'a rien à faire sonore.
    func pauseMedia() {
        guard hasContent else { return }
        webView.evaluateJavaScript(ScriptInjectionService.pauseAllMediaScript,
                                   completionHandler: nil)
    }

    /// Une musique joue : les vidéos de ce compartiment restent muettes pour
    /// ne pas la couper (cf. `MusicPriorityService`).
    var mutesForMusic = false {
        didSet {
            guard mutesForMusic != oldValue else { return }
            applyMusicMute()
        }
    }

    private func applyMusicMute() {
        guard hasContent else { return }
        webView.evaluateJavaScript(MusicPriorityService.setMutedScript(mutesForMusic),
                                   completionHandler: nil)
    }

    /// Marge basse pour la barre d'outils, comme sur la webview YouTube.
    func setBottomMargin(visible: Bool) {
        guard hasContent else { return }
        let px = visible ? "60px" : "0px"
        webView.evaluateJavaScript("document.body.style.paddingBottom = '\(px)';",
                                   completionHandler: nil)
    }
}

// MARK: - Sessions

/// Les compartiments ouverts, un par site visité.
///
/// Créés à la demande — une webview qu'on n'a jamais ouverte ne coûte rien — et
/// gardés ensuite : c'est ce qui rend le retour instantané.
final class SiteSessions: ObservableObject {

    @Published private(set) var sessions: [SiteKind: SiteWebViewModel] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// L'ordre de création, pour donner à SwiftUI une liste stable à empiler.
    @Published private(set) var order: [SiteKind] = []

    func session(for kind: SiteKind) -> SiteWebViewModel {
        if let existing = sessions[kind] { return existing }
        let created = SiteWebViewModel(site: kind)
        created.mutesForMusic = mutesForMusic
        created.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sessions[kind] = created
        order.append(kind)
        return created
    }

    func existing(_ kind: SiteKind) -> SiteWebViewModel? { sessions[kind] }

    /// Met en sourdine tous les compartiments sauf celui qu'on affiche.
    func pauseAll(except kind: SiteKind? = nil) {
        for (siteKind, session) in sessions where siteKind != kind {
            session.pauseMedia()
        }
    }

    /// Silence imposé aux vidéos de tous les compartiments, y compris ceux
    /// créés ensuite, tant qu'une musique joue.
    var mutesForMusic = false {
        didSet { sessions.values.forEach { $0.mutesForMusic = mutesForMusic } }
    }

    func setBottomMargin(visible: Bool) {
        sessions.values.forEach { $0.setBottomMargin(visible: visible) }
    }
}
