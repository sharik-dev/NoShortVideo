//
//  ContentView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Combine
import StoreKit
import SwiftUI

struct ContentView: View {

    @StateObject private var viewModel   = YouTubeWebViewModel()
    @StateObject private var musicVM     = MusicWebViewModel()
    /// Les compartiments des réseaux sociaux, créés au premier usage.
    @StateObject private var sites       = SiteSessions()
    /// Le compartiment affiché. Chacun garde sa page : changer de compartiment
    /// ne charge rien, ça ne fait que changer ce qu'on voit.
    @State private var panel: BrowserPanel = .youtube
    @State private var showLibrary       = false
    @State private var showMusicLibrary  = false
    /// Rayon ouvert dans la bibliothèque de l'accueil, gardé d'une fois sur l'autre.
    /// Vidéo téléchargée en cours de lecture hors ligne.
    @State private var offlineVideo: SavedVideo?
    /// Lecteur des MP3 hors ligne, plein écran (depuis la mini-barre).
    @State private var showMusicPlayer   = false
    @ObservedObject private var offlineMusic = OfflineMusicPlayer.shared
    @State private var showToolbar       = true
    @State private var showSettings      = false
    @State private var showStats         = false
    @State private var showHome          = false  // set by onAppear based on onboarding state

    @AppStorage("gaugeEnabled")          private var gaugeEnabled: Bool    = false
    @AppStorage("statsEnabled")          private var statsEnabled: Bool    = false
    @AppStorage("appLanguage")           private var lang: String          = "en"
    @AppStorage("hasSeenOnboarding")     private var hasSeenOnboarding: Bool = false
    @AppStorage("hasSeenQuickstart")     private var hasSeenQuickstart: Bool = false
    /// Téléchargements arrivés depuis la dernière ouverture de la bibliothèque.
    @AppStorage(VideoDownloadService.unseenKey) private var unseenDownloads: Int = 0
    @AppStorage(VideoDownloadService.unseenMusicKey) private var unseenMusicDownloads: Int = 0

    @State private var showOnboarding    = false
    @State private var showQuickstart    = false

    // Draggable collapsed toolbar bubble
    @State     private var bubbleOffset: CGSize  = .zero

    // Bandeau musique flottant (cf. musicBanner)
    @AppStorage("musicBannerFloating") private var musicFloating: Bool = false
    @State     private var musicOffset: CGSize  = .zero

    @Environment(\.scenePhase) private var scenePhase
    /// Feuille native « Noter l'app » (cf. ReviewPromptService).
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var reviewPrompt = ReviewPromptService.shared
    /// Horloge du temps passé par site (cf. `countUsage`).
    private let usageClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ZStack {
            if isCompact {
                ZStack(alignment: .bottom) {
                    webLayer
                    bottomToolbarLayer
                }
                .overlay(alignment: .leading) {
                    // Jauge de session et bouton PiP appartiennent à YouTube :
                    // ils comptent son temps et pilotent sa vidéo. Les afficher
                    // par-dessus Instagram promettait une action sans effet.
                    if panel == .youtube {
                        VStack(spacing: 14) {
                            Spacer()
                            if gaugeEnabled {
                                SessionGaugeView(viewModel: viewModel)
                            }
                            PiPFloatingButton(viewModel: viewModel)
                            // Version App Store : pas de bouton ⬇︎, seuls les
                            // favoris musicaux se téléchargent, d'eux-mêmes
                            // (cf. VideoDownloadService). DEBUG le garde.
                            #if DEBUG
                            if VideoDownloadService.showsManualDownloads,
                               viewModel.webViewState.isOnVideoPage {
                                DownloadFloatingButton(
                                    videoId: viewModel.webViewState.currentVideoId,
                                    action: { viewModel.downloadCurrentVideo() }
                                )
                            }
                            #endif
                            Spacer().frame(height: 84)
                        }
                        .padding(.leading, 6)
                    } else if panel == .music && VideoDownloadService.showsManualDownloads {
                        #if DEBUG
                        // YouTube Music : téléchargement en MP3 uniquement.
                        VStack {
                            Spacer()
                            DownloadFloatingButton(format: .mp3) { musicVM.downloadCurrentTrack() }
                            Spacer().frame(height: 84)
                        }
                        .padding(.leading, 6)
                        #endif
                    }
                }
            } else {
                HStack(spacing: 0) {
                    webLayer
                    trailingToolbarLayer
                }
            }

            if statsEnabled {
                VStack {
                    LiveStatsView()
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4), value: statsEnabled)
            }

            if viewModel.showSavedFeedback || musicVM.showSavedFeedback {
                savedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: viewModel.showSavedFeedback)
            }

            #if DEBUG
            if VideoDownloadService.showsManualDownloads {
                DownloadPillOverlay(onOpenLibrary: { openLibrary() })
            }
            #endif

            if viewModel.isBlocked && panel == .youtube {
                blockedOverlay
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.isBlocked)
            }
        }
        .overlay(alignment: musicFloating ? .bottomTrailing : .bottom) {
            musicBanner
        }
        .fullScreenCover(isPresented: $showMusicPlayer) {
            MusicPlayerView()
        }
        // Deux sons à la fois n'ont aucun sens : un MP3 qui démarre coupe le
        // web, et une vidéo YouTube ou YouTube Music qui démarre coupe le MP3.
        .onChange(of: offlineMusic.isPlaying) { _, playing in
            guard playing else { return }
            musicVM.pauseForVideo()
            viewModel.pauseMedia()
        }
        .onChange(of: musicVM.isPlaying) { _, playing in
            if playing { offlineMusic.pause() }
        }
        // Sur Instagram, X… la musique passe avant le fil : tant qu'elle joue,
        // les vidéos de ces pages restent muettes (cf. MusicPriorityService).
        .onChange(of: musicVM.isPlaying || offlineMusic.isPlaying, initial: true) { _, playing in
            sites.mutesForMusic = playing
        }
        // Une vidéo YouTube qui démarre coupe la musique : deux sons en même
        // temps n'ont aucun sens. La session reste ouverte, la bannière aussi.
        .onReceive(viewModel.webViewState.$isOnVideoPage) { isOnVideo in
            if isOnVideo && panel == .youtube {
                musicVM.pauseForVideo()
                offlineMusic.pause()
            }
        }
        // Sur YouTube, la webview musicale n'a rien à faire : la musique y est
        // déjà mise en pause, et la laisser chargée maintenait une deuxième
        // page Google authentifiée et active en arrière-plan. Elle se recharge
        // à la position exacte dès qu'on y revient.
        .onReceive(viewModel.$currentSite) { site in
            guard panel == .youtube else { return }
            if site == .youtube {
                // Laisser `pauseForVideo` s'appliquer d'abord : `suspendIfIdle`
                // ne fait rien tant qu'un morceau joue.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    musicVM.suspendIfIdle()
                }
            }
        }
        .overlayPreferenceValue(CoachMarkBoundsKey.self) { anchors in
            if showQuickstart {
                QuickstartOverlay(isPresented: $showQuickstart, anchors: anchors)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showQuickstart)
            }
        }
        .onAppear {
            viewModel.loadYouTube()
            #if DEBUG
            // Test du téléchargement sans toucher l'écran :
            // `simctl launch … -debugDownload <videoId> [-debugProvider yt1s]`
            let args = UserDefaults.standard
            if args.object(forKey: "debugPillCollapsed") != nil {
                UserDefaults.standard.set(args.bool(forKey: "debugPillCollapsed"), forKey: "downloadPillCollapsed")
            }
            if args.bool(forKey: "debugSkipHome") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false }
            }
            if let id = args.string(forKey: "debugOpenVideo"),
               let url = URL(string: "https://m.youtube.com/watch?v=\(id)") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false; viewModel.loadURL(url) }
            }
            // `-debugOpenURL <url>` : n'importe quelle page, dans son compartiment
            // (une page YouTube Music s'ouvre dans la webview musique).
            if let raw = args.string(forKey: "debugOpenURL"), let url = URL(string: raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showHome = false
                    if SiteKind.isMusic(url) {
                        open(url, isShortcut: true)
                        if url.path == "/watch" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { musicVM.debugLoad(url) }
                        }
                    } else {
                        open(url, isShortcut: false)
                    }
                }
            }
            // `-debugOpenURL2 <url>` : une seconde page, 14 s plus tard — pour
            // montrer le mini-lecteur pendant qu'on navigue ailleurs.
            if let raw = args.string(forKey: "debugOpenURL2"), let url = URL(string: raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 14) { open(url, isShortcut: false) }
            }
            if args.bool(forKey: "debugMusicPlayer"),
               let track = VideoStorageService.music.loadAll().first(where: { $0.isOffline }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    offlineMusic.play(track, in: VideoStorageService.music.loadAll())
                    showMusicPlayer = true
                }
            }
            if args.bool(forKey: "debugReview") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reviewPrompt.debugForce() }
            }
            if args.bool(forKey: "debugOpenStats") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showStats = true }
            }
            if args.bool(forKey: "debugOpenDownloads") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { openLibrary() }
            }
            if let id = args.string(forKey: "debugPlayOffline"),
               let video = VideoStorageService.shared.loadAll().first(where: { $0.id == id }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHome = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { offlineVideo = video }
            }
            if let id = args.string(forKey: "debugDownload") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showHome = false }
                VideoDownloadService.shared.debugOnlyProvider =
                    args.string(forKey: "debugProvider").flatMap(DownloadProvider.init(rawValue:))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let format = args.string(forKey: "debugFormat").flatMap(DownloadFormat.init(rawValue:)) ?? .mp4
                    VideoDownloadService.shared.start(videoId: id, title: "Debug \(id)", duration: 0, format: format)
                }
            }
            #endif
            if !hasSeenOnboarding {
                showOnboarding = true
            } else {
                showHome = true
                if !hasSeenQuickstart {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        showQuickstart = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
                if !hasSeenQuickstart {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        showQuickstart = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showHome) {
            BrowserHomeView(
                isPresented: $showHome,
                onOpen: open,
                // Laisser l'accueil se refermer avant de présenter la feuille.
                onOpenLibrary: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openLibrary() }
                },
                onOpenStats: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showStats = true }
                }
            )
        }
        .sheet(isPresented: $showStats) {
            UsageStatsView()
        }
        .onReceive(usageClock) { _ in countUsage() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                reviewPrompt.recordActiveDay()
                // Un téléchargement coupé par la sortie de l'app repart ici.
                VideoDownloadService.shared.resumePending()
            }
        }
        .onChange(of: reviewPrompt.isDue) { _, due in
            guard due else { return }
            askForReviewIfCalm()
        }
        .sheet(isPresented: $showLibrary) {
            // Des dossiers plutôt qu'un sélecteur : Vidéos, Musique, et ceux
            // que l'utilisateur crée pour y ranger les deux.
            HomeLibraryView(
                isPresented: $showLibrary,
                onOpenVideo: openSavedVideo,
                onOpenTrack: openSavedTrack
            )
        }
        .fullScreenCover(item: $offlineVideo) { video in
            OfflinePlayerScreen(video: video)
        }
        .sheet(isPresented: $showMusicLibrary) {
            musicLibrary(isPresented: $showMusicLibrary)
        }
        .alert(t("Enregistrement impossible", "Can't save"),
               isPresented: Binding(
                   get: { musicVM.saveErrorMessage != nil },
                   set: { if !$0 { musicVM.saveErrorMessage = nil } }
               )) {
            Button("OK", role: .cancel) { musicVM.saveErrorMessage = nil }
        } message: {
            Text(musicVM.saveErrorMessage ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert(t("Erreur de sauvegarde", "Save Error"),
               isPresented: $viewModel.showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveErrorMessage)
        }
    }

    // MARK: - Bibliothèques

    private func musicLibrary(isPresented: Binding<Bool>) -> some View {
        LibraryView(
            isPresented: isPresented,
            storage: .music,
            navigationTitle: t("Musique", "Music"),
            accent: Color(red: 1, green: 0.18, blue: 0.33),
            emptyTitle: ("Aucun morceau", "No Saved Tracks"),
            emptyHint: (
                "Appuyez sur le marque-page pendant\nla lecture pour enregistrer un morceau.",
                "Tap the bookmark icon while a track\nis playing to save it here."
            ),
            downloadFormat: .mp3,
            onOpen: openSavedTrack
        )
    }

    private func openSavedVideo(_ video: SavedVideo) {
        show(.youtube)
        if video.isOffline {
            // Téléchargée : lecture locale, sans réseau. YouTube se
            // tait, deux sons à la fois n'ont aucun sens.
            viewModel.pauseMedia()
            musicVM.pauseForVideo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { offlineVideo = video }
        } else {
            viewModel.openVideo(video)
        }
    }

    private func openSavedTrack(_ track: SavedVideo) {
        if track.isOffline {
            // MP3 téléchargé : lecture locale, la session YouTube Music
            // se tait.
            musicVM.pauseForVideo()
            viewModel.pauseMedia()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { offlineVideo = track }
        } else {
            show(.music)
            musicVM.openTrack(track)
        }
    }

    // MARK: - Bandeau musique

    /// Le bandeau de ce qui joue : la mini-barre des MP3 hors ligne, sinon
    /// celui de YouTube Music (hors de son propre compartiment).
    ///
    /// Les deux se masquent de la même façon — chevron à droite → bulle ronde
    /// qu'on déplace au doigt, un appui dessus rouvre le bandeau — et partagent
    /// le même état : masquer l'un, c'est masquer l'autre.
    ///
    /// Le déplacement vit ici et pas dans la bulle : elle ne connaît pas
    /// l'écran, et l'offset doit survivre à ses redessins (le titre change à
    /// chaque morceau).
    @ViewBuilder
    private var musicBanner: some View {
        let hasOffline = offlineMusic.current != nil
        let hasStream  = musicVM.hasSession && panel != .music

        if hasOffline || hasStream {
            Group {
                if musicFloating {
                    Group {
                        if hasOffline {
                            MusicMiniBubble()
                        } else {
                            MusicBubble(isPlaying: musicVM.isPlaying) {
                                MusicBubbleIcon(isPlaying: musicVM.isPlaying)
                            }
                        }
                    }
                    .floatingDrag(offset: $musicOffset, onTap: expandMusicBanner)
                    .padding(.trailing, 14)
                    .padding(.bottom, showToolbar ? 78 : 18)
                    .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity))
                } else {
                    Group {
                        if hasOffline {
                            MusicMiniBar(onOpen: { showMusicPlayer = true }, onHide: hideMusicBanner)
                        } else {
                            MusicMiniPlayerView(musicVM: musicVM,
                                                onOpen: { show(.music) },
                                                onHide: hideMusicBanner)
                        }
                    }
                    .padding(.bottom, showToolbar ? 78 : 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: offlineMusic.current?.id)
            .animation(.spring(response: 0.35), value: musicVM.hasSession)
        }
    }

    private func hideMusicBanner() {
        withAnimation(.spring(response: 0.35)) { musicFloating = true }
    }

    /// Rouvrir remet la bulle à sa place : sinon elle réapparaîtrait décalée
    /// au prochain masquage.
    private func expandMusicBanner() {
        withAnimation(.spring(response: 0.35)) {
            musicFloating = false
            musicOffset = .zero
        }
    }

    // MARK: - Couche web

    /// Toutes les webviews cohabitent, empilées : YouTube, YouTube Music, et un
    /// compartiment par réseau social ouvert. On change la visibilité, jamais
    /// la hiérarchie — retirer une webview de l'écran coupe sa lecture, et la
    /// remonter repart d'une page blanche.
    ///
    /// C'est ce qui supprime la demi-seconde où l'on voyait encore le site
    /// précédent : la page d'arrivée existe déjà, elle n'a rien à charger.
    private var webLayer: some View {
        ZStack {
            YouTubeWebView(webView: viewModel.webView)
                .opacity(panel == .youtube ? 1 : 0)
                .allowsHitTesting(panel == .youtube)

            if musicVM.hasSession {
                YouTubeWebView(webView: musicVM.webView)
                    .opacity(panel == .music ? 1 : 0)
                    .allowsHitTesting(panel == .music)
            }

            ForEach(sites.order, id: \.self) { kind in
                if let session = sites.existing(kind) {
                    let visible = panel == .site(kind)
                    YouTubeWebView(webView: session.webView)
                        .opacity(visible ? 1 : 0)
                        .allowsHitTesting(visible)
                        .overlay {
                            // Première ouverture : la webview est encore
                            // blanche. On la couvre plutôt que de montrer ce
                            // blanc — et surtout plutôt que de laisser le site
                            // précédent à l'écran, ce qu'on faisait avant.
                            if visible && !session.isReady {
                                loadingCover(for: kind)
                            }
                        }
                }
            }
        }
    }

    /// Voile posé sur un compartiment qui charge sa première page.
    private func loadingCover(for kind: SiteKind) -> some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }

    /// Ouvre la bibliothèque et éteint la pastille rouge des nouveaux
    /// téléchargements : les voir, c'est les avoir vus.
    private func openLibrary() {
        unseenDownloads = 0
        showLibrary = true
    }

    // MARK: - Cloisonnement

    /// Passe d'un compartiment à l'autre.
    ///
    /// Le compartiment qu'on quitte **se tait** : c'est toute la demande — une
    /// vidéo YouTube n'a rien à continuer sous YouTube Music. Sa page, elle,
    /// reste intacte et reprend là où on l'avait laissée.
    ///
    /// La musique est la seule exception : elle a le droit de continuer quand
    /// on navigue ailleurs, c'est la raison d'être de sa webview séparée et du
    /// bandeau qui la pilote. Elle s'arrête tout de même côté YouTube, où
    /// `pauseForVideo` prend le relais.
    private func show(_ target: BrowserPanel) {
        guard target != panel else { return }

        switch panel {
        case .youtube:
            viewModel.setPanelActive(false)
        case .music:
            break
        case .site(let kind):
            sites.existing(kind)?.pauseMedia()
        }

        panel = target
        // Sur un réseau social, une coupure du son ne fait pas attendre la
        // musique la fin de la vidéo fautive (cf. AudioInterruptionMonitor).
        if case .site = target {
            AudioInterruptionMonitor.musicHasPriority = true
        } else {
            AudioInterruptionMonitor.musicHasPriority = false
        }

        switch target {
        case .youtube:
            viewModel.setPanelActive(true)
        case .music:
            musicVM.resume()
        case .site(let kind):
            sites.pauseAll(except: kind)
        }
    }

    /// Ouvre un raccourci de l'écran d'accueil, ou une adresse tapée.
    ///
    /// `isShortcut` distingue les deux : une tuile **revient** au site tel qu'on
    /// l'avait laissé (elle ne recharge rien), alors qu'une URL tapée ou une
    /// recherche demande explicitement cette page-là.
    private func open(_ url: URL, isShortcut: Bool) {
        SiteUsageStore.shared.recordOpen(
            SiteKind.isMusic(url) ? .music : UsageSite(SiteKind.detect(url))
        )
        if SiteKind.isMusic(url) {
            show(.music)
            musicVM.openMusic()
            return
        }

        let kind = SiteKind.detect(url)

        if kind == .youtube {
            show(.youtube)
            if !isShortcut || viewModel.webViewState.currentURL == nil {
                viewModel.loadURL(url)
            }
            return
        }

        let session = sites.session(for: kind)
        show(.site(kind))
        if isShortcut {
            session.open(url)
        } else {
            session.load(url)
        }
    }

    // MARK: - Statistiques

    /// Le site réellement regardé : dans le compartiment YouTube, une page
    /// ouverte depuis un lien peut être n'importe quel autre site.
    private var usageSite: UsageSite {
        switch panel {
        case .youtube:         return UsageSite(viewModel.currentSite)
        case .music:           return .music
        case .site(let kind):  return UsageSite(kind)
        }
    }

    /// Une seconde de plus sur le site affiché — seulement quand on le
    /// regarde vraiment : pas en arrière-plan, pas derrière l'accueil, une
    /// feuille, le lecteur hors ligne ou l'écran de blocage.
    private func countUsage() {
        guard scenePhase == .active,
              !showHome, !showOnboarding, !showStats, !showSettings,
              !showLibrary, !showMusicLibrary, offlineVideo == nil,
              !(panel == .youtube && viewModel.isBlocked)
        else { return }
        SiteUsageStore.shared.tick(usageSite)
    }

    // MARK: - Note App Store

    /// Pose la feuille à étoiles seulement si l'écran est libre : pas pendant
    /// l'onboarding, le blocage de session ou une vidéo hors ligne en plein
    /// écran. Sinon, on attend la prochaine réussite.
    private func askForReviewIfCalm() {
        guard scenePhase == .active,
              !showOnboarding, !showQuickstart, offlineVideo == nil, !showMusicPlayer,
              !(panel == .youtube && viewModel.isBlocked)
        else {
            reviewPrompt.postpone()
            return
        }
        requestReview()
        reviewPrompt.didAsk()
    }

    // MARK: - Barre d'outils

    /// Ce que la barre d'outils doit montrer pour le compartiment affiché.
    ///
    /// Favori et bibliothèque n'apparaissent que là où il y a quelque chose à
    /// enregistrer — une vidéo YouTube ou un morceau. Sur Instagram, LinkedIn,
    /// X ou Twitch, ils promettaient une action qui échouait (cf. `SiteKind`).
    private var toolbarConfig: BrowserToolbarConfig {
        switch panel {
        case .youtube:
            return BrowserToolbarConfig(
                canGoBack: viewModel.webViewState.canGoBack,
                canGoForward: viewModel.webViewState.canGoForward,
                showsBookmark: viewModel.currentSite.showsBookmark,
                showsLibrary: viewModel.currentSite.showsLibrary,
                libraryIcon: "books.vertical",
                libraryBadge: unseenDownloads > 0,
                onBack:    { viewModel.goBack() },
                onForward: { viewModel.goForward() },
                onReload:  { viewModel.reload() },
                onBookmark: { viewModel.saveCurrentVideo() },
                onLibrary:  { openLibrary() }
            )

        case .music:
            // YouTube Music est une SPA : son historique ne remonte pas dans
            // `canGoBack`, donc les flèches restent actives.
            return BrowserToolbarConfig(
                canGoBack: true,
                canGoForward: true,
                showsBookmark: true,
                showsLibrary: true,
                libraryIcon: "music.note.list",
                libraryBadge: unseenMusicDownloads > 0,
                onBack:    { musicVM.goBack() },
                onForward: { musicVM.goForward() },
                onReload:  { musicVM.reload() },
                onBookmark: { musicVM.saveCurrentTrack() },
                onLibrary:  { unseenMusicDownloads = 0; showMusicLibrary = true }
            )

        case .site(let kind):
            let session = sites.existing(kind)
            return BrowserToolbarConfig(
                canGoBack: session?.state.canGoBack ?? false,
                canGoForward: session?.state.canGoForward ?? false,
                showsBookmark: false,
                showsLibrary: false,
                onBack:    { session?.goBack() },
                onForward: { session?.goForward() },
                onReload:  { session?.reload() }
            )
        }
    }

    /// La marge basse est celle de la barre d'outils : elle vaut pour tous les
    /// compartiments, pas seulement celui qu'on regarde.
    private func setBottomMargin(visible: Bool) {
        viewModel.setBottomMargin(visible: visible)
        sites.setBottomMargin(visible: visible)
    }

    // MARK: - Bottom Toolbar (iPhone)

    @ViewBuilder
    private var bottomToolbarLayer: some View {
        if showToolbar {
            VStack(spacing: 0) {
                Spacer()
                ToolbarView(
                    config: toolbarConfig,
                    onCollapse: {
                        withAnimation(.spring(response: 0.35)) { showToolbar = false }
                        setBottomMargin(visible: false)
                    },
                    onHome:     { showHome     = true },
                    onSettings: { showSettings = true }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            draggableBubble
        }
    }

    // MARK: - Draggable collapsed bubble
    // `floatingDrag` so a drag-release never accidentally re-opens the toolbar.

    private var draggableBubble: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .ultraThinMaterial)
                    .shadow(color: .white.opacity(0.25), radius: 12)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .floatingDrag(offset: $bubbleOffset) {
                        withAnimation(.spring(response: 0.35)) { showToolbar = true }
                        setBottomMargin(visible: true)
                    }
                    .padding(.bottom, 18)
                    .padding(.trailing, 18)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Trailing Toolbar (iPad / Mac)

    @ViewBuilder
    private var trailingToolbarLayer: some View {
        if showToolbar {
            ToolbarView(
                config: toolbarConfig,
                onCollapse:  { withAnimation(.spring(response: 0.35)) { showToolbar = false } },
                onHome:      { showHome     = true },
                onSettings:  { showSettings = true }
            )
            .padding(.vertical, 12)
            .padding(.trailing, 6)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            VStack {
                Button {
                    withAnimation(.spring(response: 0.35)) { showToolbar = true }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 40))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(.systemGray2))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .padding(.top, 20).padding(.trailing, 14)
                Spacer()
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Saved Toast

    private var savedToast: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(t("Sauvegardé", "Saved to Library"))
                    .font(.subheadline).fontWeight(.semibold)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Blocked Overlay

    private var blockedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "timer")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text(t("Limite atteinte", "Limit reached"))
                        .font(.title2.bold())
                    Text(t(
                        "Tu as utilisé ton temps YouTube pour cette session.\nAugmente la limite dans les paramètres pour continuer.",
                        "You've used your YouTube time for this session.\nIncrease the limit in settings to continue."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                Button {
                    showSettings = true
                } label: {
                    Label(t("Paramètres", "Settings"), systemImage: "gearshape")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(.top, 4)
            }
        }
    }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }
}

#Preview { ContentView() }
