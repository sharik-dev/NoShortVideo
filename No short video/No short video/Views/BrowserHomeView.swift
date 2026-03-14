//
//  BrowserHomeView.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

struct BrowserHomeView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @Binding var isPresented: Bool

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

                Spacer().frame(height: 36)

                // ── Favourite label ──
                Text(t("Favoris", "Favourites"))
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                // ── Tiles ──
                HStack(spacing: 16) {
                    FavTile(
                        name: "YouTube",
                        icon: "play.rectangle.fill",
                        color: Color(red: 1, green: 0, blue: 0),
                        urlString: "https://m.youtube.com"
                    ) { url in viewModel.loadURL(url); isPresented = false }

                    FavTile(
                        name: "Twitch",
                        icon: "gamecontroller.fill",
                        color: Color(red: 0.57, green: 0.27, blue: 1),
                        urlString: "https://m.twitch.tv"
                    ) { url in viewModel.loadURL(url); isPresented = false }

                    Spacer()
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isSearchFocused = true }
        }
    }

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
            if let url = URL(string: q) { viewModel.loadURL(url) }
        } else if q.contains(".") && !q.contains(" ") {
            if let url = URL(string: "https://\(q)") { viewModel.loadURL(url) }
        } else {
            viewModel.search(q)
        }
        isPresented = false
    }
}

// MARK: - FavTile

private struct FavTile: View {
    let name: String
    let icon: String
    let color: Color
    let urlString: String
    let onTap: (URL) -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            guard let url = URL(string: urlString) else { return }
            onTap(url)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(color.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [color.opacity(0.6), color.opacity(0.15)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(color)
                        .shadow(color: color.opacity(0.3), radius: 6, y: 2)
                }
                .frame(width: 88, height: 88)
                .shadow(color: color.opacity(0.18), radius: 12, y: 4)

                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.93 : 1)
        .onLongPressGesture(
            minimumDuration: 100,
            pressing: { p in withAnimation(.easeInOut(duration: 0.12)) { pressed = p } },
            perform: {}
        )
    }
}
