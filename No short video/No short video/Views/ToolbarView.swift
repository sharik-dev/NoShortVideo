//
//  ToolbarView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Ce que la barre d'outils doit afficher et déclencher pour le compartiment
/// actuellement à l'écran.
///
/// La barre ne connaît plus les modèles : YouTube, YouTube Music et chaque
/// réseau social ont leur propre webview (cf. `SiteWebViewModel`), et c'est
/// ContentView — seul à savoir lequel est affiché — qui remplit cette
/// description. Sans elle, il fallait un `if isShowingMusic` par bouton.
struct BrowserToolbarConfig {
    var canGoBack: Bool
    var canGoForward: Bool
    /// Le favori et la bibliothèque n'existent que là où il y a quelque chose à
    /// enregistrer : YouTube et YouTube Music (cf. `SiteKind`).
    var showsBookmark: Bool = false
    var showsLibrary: Bool = false
    var libraryIcon: String = "books.vertical"
    /// Pastille rouge sur la bibliothèque : un téléchargement y est arrivé.
    var libraryBadge: Bool = false
    var onBack: () -> Void
    var onForward: () -> Void
    var onReload: () -> Void
    var onBookmark: () -> Void = {}
    var onLibrary: () -> Void = {}
}

/// Adaptive toolbar: horizontal bottom bar on iPhone, vertical right bar on iPad/Mac.
/// Glass styling with per-icon glow, matching and exceeding the SessionGaugeView aesthetic.
struct ToolbarView: View {

    let config: BrowserToolbarConfig
    var onCollapse: () -> Void
    var onHome: () -> Void
    var onSettings: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        let layout = isCompact
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            toolbarButton(icon: "chevron.left", disabled: !config.canGoBack) { config.onBack() }
                .coachMark(.back)

            toolbarButton(icon: "chevron.right", disabled: !config.canGoForward) { config.onForward() }
                .coachMark(.forward)

            if config.showsBookmark {
                toolbarButton(icon: "bookmark.fill", disabled: false, accent: true) { config.onBookmark() }
                    .coachMark(.bookmark)
            }

            if config.showsLibrary {
                toolbarButton(icon: config.libraryIcon, disabled: false) { config.onLibrary() }
                    .overlay(alignment: .center) {
                        if config.libraryBadge {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                                .offset(x: 12, y: -11)
                                .shadow(color: .red.opacity(0.7), radius: 4)
                                .allowsHitTesting(false)
                        }
                    }
                    .coachMark(.library)
            }

            toolbarButton(icon: "arrow.clockwise", disabled: false) { config.onReload() }
                .coachMark(.reload)

            toolbarButton(icon: "house",
                          disabled: false) { onHome() }
                .coachMark(.home)

            toolbarButton(icon: "gearshape",
                          disabled: false) { onSettings() }
                .coachMark(.settings)

            toolbarButton(icon: isCompact ? "chevron.down" : "chevron.right",
                          disabled: false) { onCollapse() }
                .coachMark(.collapse)
        }
        .padding(isCompact ? .vertical : .horizontal, 10)
        .background(glassBackground)
    }

    // MARK: - Glass background with strong upward glow

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // Multi-layer glow matching gauge aesthetic but stronger
            .shadow(color: .white.opacity(0.18), radius: 18, y: isCompact ? -6 : 0)
            .shadow(color: .white.opacity(0.08), radius: 32, y: isCompact ? -12 : 0)
            .shadow(color: .black.opacity(0.18), radius: 10, y: isCompact ? -3 : 0)
    }

    // MARK: - Button with per-icon glow

    private func toolbarButton(
        icon: String,
        disabled: Bool,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            let iconColor: Color = disabled ? Color(.systemGray3) : accent ? .red : .white
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                // Tight core glow
                .shadow(color: disabled ? .clear : (accent ? .red.opacity(0.7) : .white.opacity(0.55)),
                        radius: 5)
                // Wide halo glow
                .shadow(color: disabled ? .clear : (accent ? .red.opacity(0.35) : .white.opacity(0.25)),
                        radius: 14)
                .frame(maxWidth: isCompact ? .infinity : nil)
                .frame(width: isCompact ? nil : 38, height: 38)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}
