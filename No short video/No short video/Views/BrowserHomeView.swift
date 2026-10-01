//
//  BrowserHomeView.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

struct BrowserHomeView: View {

    @Binding var isPresented: Bool
    /// ContentView décide où charger : chaque site a sa propre webview.
    ///
    /// Le second argument distingue une **tuile** (on revient au site tel qu'on
    /// l'avait laissé, sans rien recharger) d'une adresse tapée ou d'une
    /// recherche, qui demande explicitement cette page-là.
    var onOpen: (URL, Bool) -> Void
    /// Ouvre la bibliothèque (favoris + vidéos hors ligne).
    var onOpenLibrary: () -> Void = {}
    /// Ouvre les statistiques d'utilisation par site.
    var onOpenStats: () -> Void = {}

    @AppStorage(VideoDownloadService.unseenKey) private var unseenDownloads: Int = 0
    /// Nombre de vidéos disponibles hors ligne, affiché sous la tuile.
    @State private var offlineCount = 0
    /// Temps passé aujourd'hui, tous sites confondus.
    @State private var todayUsage: Double = 0

    @AppStorage("appLanguage") private var lang: String = "en"
    @AppStorage(HomeCatView.enabledKey) private var catEnabled = true
    @AppStorage("dailyLimitMinutes") private var dailyLimitMinutes = 60
    /// Cadres des tuiles, pour que le chat puisse s'y asseoir.
    @State private var catPerches: [CGRect] = []


    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──
                // Les tuiles mènent aussi bien à de la musique, des réseaux
                // sociaux ou la bibliothèque qu'à de la vidéo : le titre ne
                // parle donc plus de « regarder », mais de la promesse de
                // l'app — le web habituel, sans les vidéos courtes.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(greeting.text, systemImage: greeting.icon)
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(Self.tileAccent)
                        Text(t("Où va-t-on ?", "Where to?"))
                            .font(.largeTitle.bold())
                        Text(t("Tes sites habituels, sans les vidéos courtes.",
                               "Your usual sites, minus the short videos."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("Fermer", "Close"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)

                // ── Tiles ──
                // Six raccourcis : trois plateformes vidéo, puis les trois
                // réseaux sociaux, dont seules les vidéos courtes sont
                // retirées (cf. SocialShortsService). Puis bibliothèque et
                // statistiques : trois rangées de trois.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t("Favoris", "Favourites"))
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 14)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                            spacing: 18
                        ) {
                            ForEach(Self.favourites) { fav in
                                FavTile(name: fav.name, icon: fav.icon) {
                                    guard let url = URL(string: fav.urlString) else { return }
                                    onOpen(url, true)
                                    isPresented = false
                                }
                            }
                            // Accès direct aux vidéos téléchargées : c'est ce
                            // qu'on veut ouvrir sans réseau, sans passer par
                            // YouTube d'abord.
                            FavTile(
                                name: t("Librairie", "Library"),
                                icon: "books.vertical.fill",
                                caption: offlineCount > 0 && VideoDownloadService.showsManualDownloads
                                    ? t("\(offlineCount) hors ligne", "\(offlineCount) offline") : nil,
                                badge: unseenDownloads > 0 && VideoDownloadService.showsManualDownloads
                            ) {
                                isPresented = false
                                onOpenLibrary()
                            }
                            FavTile(
                                name: t("Stats", "Stats"),
                                icon: "chart.bar.fill",
                                caption: todayUsage > 0
                                    ? t("\(SiteUsageStore.format(todayUsage)) auj.",
                                        "\(SiteUsageStore.format(todayUsage)) today") : nil
                            ) {
                                isPresented = false
                                onOpenStats()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                // Bande réservée au chat : il y marche, sous les tuiles.
                if catEnabled {
                    Color.clear
                        .frame(height: HomeCatView.groundHeight)
                        .padding(.bottom, 8)
                }
            }

            // Le chat de l'accueil, dans la couleur des tuiles. Par-dessus
            // tout l'écran pour pouvoir grimper sur les tuiles.
            if catEnabled {
                HomeCatView(
                    color: Self.tileAccent,
                    perches: catPerches,
                    drowsiness: todayUsage / Double(max(1, dailyLimitMinutes) * 60)
                )
            }
        }
        .coordinateSpace(.named(HomeCatView.space))
        .onPreferenceChange(CatPerchKey.self) { catPerches = $0 }
        .onAppear {
            offlineCount = VideoStorageService.shared.loadAll().filter(\.isOffline).count
            todayUsage = SiteUsageStore.shared.seconds(on: Date())
        }
    }

    // MARK: - Favourites

    fileprivate struct Favourite: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let urlString: String
    }

    /// Une seule teinte pour toutes les tuiles. Reprendre la couleur de chaque
    /// marque donnait six accents qui se battaient dans un écran de 120 points
    /// de haut ; le rouge de l'app suffit à faire tenir la grille ensemble.
    fileprivate static let tileAccent = Color(red: 1, green: 0, blue: 0)

    /// Chaque raccourci ouvre l'accueil du site, comme YouTube ouvre le sien.
    /// La seule chose que l'app retire ensuite, ce sont les vidéos courtes
    /// (cf. SocialShortsService) — le reste de la page est celle d'origine.
    fileprivate static let favourites: [Favourite] = [
        Favourite(name: "YouTube",   icon: "play.rectangle.fill",
                  urlString: "https://m.youtube.com"),
        Favourite(name: "YT Music",  icon: "music.note",
                  urlString: "https://music.youtube.com"),
        Favourite(name: "Twitch",    icon: "gamecontroller.fill",
                  urlString: "https://m.twitch.tv"),
        Favourite(name: "Instagram", icon: "camera.fill",
                  urlString: "https://www.instagram.com/"),
        Favourite(name: "LinkedIn",  icon: "briefcase.fill",
                  urlString: "https://www.linkedin.com/feed/"),
        Favourite(name: "X",         icon: "paperplane.fill",
                  urlString: "https://x.com/"),
    ]

    // MARK: - Helpers

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    /// Salut selon l'heure, avec le symbole qui va avec.
    private var greeting: (text: String, icon: String) {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return (t("Bonjour", "Good morning"), "sun.max.fill")
        case 12..<18: return (t("Bon après-midi", "Good afternoon"), "sun.haze.fill")
        case 18..<23: return (t("Bonsoir", "Good evening"), "moon.stars.fill")
        default:      return (t("Encore debout", "Still up"), "moon.zzz.fill")
        }
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [Color(.systemBlue).opacity(0.06), Color(.systemPurple).opacity(0.04), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - FavTile

private struct FavTile: View {
    let name: String
    let icon: String
    var caption: String? = nil
    /// Pastille rouge : du nouveau derrière cette tuile.
    var badge: Bool = false
    let onTap: () -> Void

    private var accent: Color { BrowserHomeView.tileAccent }

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(accent.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [accent.opacity(0.6), accent.opacity(0.15)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.3), radius: 6, y: 2)
                }
                .frame(width: 76, height: 76)
                .catPerch()
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
                .shadow(color: accent.opacity(0.18), radius: 12, y: 4)

                VStack(spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let caption {
                        Text(caption)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        // Identifiant stable pour les tests d'interface : le libellé seul ne
        // suffit pas — la croix de fermeture de l'écran s'appelle « X » elle
        // aussi, et une tuile nommée X est indiscernable de celle-ci.
        .accessibilityIdentifier("fav-\(name)")
        .scaleEffect(pressed ? 0.93 : 1)
        .onLongPressGesture(
            minimumDuration: 100,
            pressing: { p in withAnimation(.easeInOut(duration: 0.12)) { pressed = p } },
            perform: {}
        )
    }
}
