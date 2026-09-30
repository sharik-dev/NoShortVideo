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

    @AppStorage(VideoDownloadService.unseenKey) private var unseenDownloads: Int = 0
    /// Nombre de vidéos disponibles hors ligne, affiché sous la tuile.
    @State private var offlineCount = 0

    @AppStorage("appLanguage") private var lang: String = "en"

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Que veux-tu regarder ?", "What do you want to watch?"))
                            .font(.title2.bold())
                        Text(t("Choisis une plateforme ou recherche", "Choose a platform or search"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 28)

                // ── Search bar ──
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16, weight: .medium))

                    TextField(
                        t("Rechercher ou entrer une URL…",
                          "Search or enter a URL…"),
                        text: $searchText
                    )
                    .focused($isSearchFocused)
                    .submitLabel(.go)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { submitSearch() }

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                .padding(.horizontal, 20)

                Spacer().frame(height: 28)

                // ── Tiles ──
                // Six raccourcis : trois plateformes vidéo, puis les trois
                // réseaux sociaux, dont seules les vidéos courtes sont
                // retirées (cf. SocialShortsService). Deux rangées de trois, dans une
                // ScrollView : le champ de recherche prend le focus à
                // l'ouverture, et le clavier mangeait la seconde rangée.
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
                                caption: offlineCount > 0
                                    ? t("\(offlineCount) hors ligne", "\(offlineCount) offline") : nil,
                                badge: unseenDownloads > 0
                            ) {
                                isPresented = false
                                onOpenLibrary()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            offlineCount = VideoStorageService.shared.loadAll().filter(\.isOffline).count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isSearchFocused = true }
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

    private var backgroundGradient: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [Color(.systemBlue).opacity(0.06), Color(.systemPurple).opacity(0.04), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private func submitSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if q.hasPrefix("http://") || q.hasPrefix("https://") {
            if let url = URL(string: q) { onOpen(url, false) }
        } else if q.contains(".") && !q.contains(" ") {
            if let url = URL(string: "https://\(q)") { onOpen(url, false) }
        } else {
            // Passer par onOpen aussi pour une recherche : sinon la page se
            // charge dans la webview principale alors que YouTube Music est
            // encore au premier plan, et on ne la voit jamais.
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            if let url = URL(string: "https://m.youtube.com/results?search_query=\(encoded)") {
                onOpen(url, false)
            }
        }
        isPresented = false
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
