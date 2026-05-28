//
//  QuickstartOverlay.swift
//  No short video
//

import SwiftUI

// MARK: - Coach Mark ID

enum CoachMarkID: String, Hashable {
    case back, forward, bookmark, library, reload, home, settings, collapse
}

// MARK: - Preference Key

struct CoachMarkBoundsKey: PreferenceKey {
    typealias Value = [CoachMarkID: Anchor<CGRect>]
    static var defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - View Modifier

extension View {
    func coachMark(_ id: CoachMarkID) -> some View {
        anchorPreference(key: CoachMarkBoundsKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Steps

struct QuickstartStep {
    let id: CoachMarkID
    let icon: String
    let title: String
    let titleFR: String
    let body: String
    let bodyFR: String
}

let quickstartSteps: [QuickstartStep] = [
    QuickstartStep(
        id: .home,
        icon: "house.fill",
        title: "YouTube Home",
        titleFR: "Accueil YouTube",
        body: "Return to YouTube's home feed — shorts are automatically blocked.",
        bodyFR: "Retournez à l'accueil YouTube — les shorts sont bloqués automatiquement."
    ),
    QuickstartStep(
        id: .bookmark,
        icon: "bookmark.fill",
        title: "Save a Video",
        titleFR: "Sauvegarder une vidéo",
        body: "Tap to bookmark the current video to your library instantly.",
        bodyFR: "Tapez pour ajouter la vidéo en cours à votre bibliothèque instantanément."
    ),
    QuickstartStep(
        id: .library,
        icon: "books.vertical.fill",
        title: "Your Library",
        titleFR: "Votre bibliothèque",
        body: "All your saved videos in one place. Access them anytime.",
        bodyFR: "Toutes vos vidéos sauvegardées au même endroit, accessibles à tout moment."
    ),
    QuickstartStep(
        id: .back,
        icon: "chevron.left",
        title: "Navigate",
        titleFR: "Navigation",
        body: "Go back and forward through your browsing history, like any browser.",
        bodyFR: "Naviguez dans l'historique de navigation comme dans n'importe quel navigateur."
    ),
    QuickstartStep(
        id: .settings,
        icon: "gearshape.fill",
        title: "Settings",
        titleFR: "Paramètres",
        body: "Set daily time limits, enable Step Mode, and switch language.",
        bodyFR: "Définissez vos limites quotidiennes, activez le mode pas et changez la langue."
    ),
]

// MARK: - Overlay View

struct QuickstartOverlay: View {

    @Binding var isPresented: Bool
    @AppStorage("hasSeenQuickstart") private var hasSeenQuickstart: Bool = false
    @AppStorage("appLanguage") private var lang: String = "en"

    let anchors: CoachMarkBoundsKey.Value

    @State private var stepIndex = 0

    private var step: QuickstartStep { quickstartSteps[stepIndex] }
    private var isLast: Bool { stepIndex == quickstartSteps.count - 1 }
    private func t(_ en: String, _ fr: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let anchor = anchors[step.id] {
                    let rect = geo[anchor]
                    spotlightLayer(targetRect: rect)
                    cardLayer(targetRect: rect, screenSize: geo.size)
                } else {
                    Color.black.opacity(0.72).ignoresSafeArea()
                    cardLayer(targetRect: CGRect(x: geo.size.width / 2, y: geo.size.height - 100,
                                                 width: 44, height: 44),
                              screenSize: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Spotlight

    @ViewBuilder
    private func spotlightLayer(targetRect: CGRect) -> some View {
        // Dimmed overlay with hole punched out over the target
        Color.black.opacity(0.72)
            .ignoresSafeArea()
            .mask(
                Rectangle()
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .frame(
                                width: targetRect.width + 22,
                                height: targetRect.height + 22
                            )
                            .position(x: targetRect.midX, y: targetRect.midY)
                            .blendMode(.destinationOut)
                    }
            )

        // Highlight ring
        RoundedRectangle(cornerRadius: 16)
            .stroke(.white.opacity(0.7), lineWidth: 1.5)
            .frame(width: targetRect.width + 22, height: targetRect.height + 22)
            .position(x: targetRect.midX, y: targetRect.midY)
            .shadow(color: .white.opacity(0.35), radius: 12)
            .animation(.easeInOut(duration: 0.35), value: stepIndex)
    }

    // MARK: - Card

    @ViewBuilder
    private func cardLayer(targetRect: CGRect, screenSize: CGSize) -> some View {
        let cardWidth: CGFloat = min(screenSize.width - 40, 300)
        let cardHeight: CGFloat = 200
        let arrowH: CGFloat = 14

        // Horizontally align card center with button center (clamped to screen edges)
        let rawCX = targetRect.midX
        let cardCX = clamp(rawCX, cardWidth / 2 + 20, screenSize.width - cardWidth / 2 - 20)

        // Place card above the target button with gap for arrow
        let cardCY = targetRect.minY - arrowH - cardHeight / 2 - 16

        // Arrow horizontal offset relative to card center
        let arrowOffset = clamp(rawCX - cardCX, -(cardWidth / 2 - 28), (cardWidth / 2 - 28))

        VStack(spacing: 0) {
            // Card body
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack(spacing: 10) {
                    Image(systemName: step.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(t(step.title, step.titleFR))
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("\(stepIndex + 1) / \(quickstartSteps.count)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                // Body text
                Text(t(step.body, step.bodyFR))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                // Next / Done button
                Button {
                    advance()
                } label: {
                    Text(isLast ? t("Done ✓", "Terminer ✓") : t("Next →", "Suivant →"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(width: cardWidth)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)

            // Arrow pointing down toward target
            DownArrow()
                .fill(.ultraThinMaterial)
                .frame(width: 22, height: arrowH)
                .offset(x: arrowOffset)
        }
        .frame(width: cardWidth)
        .position(x: cardCX, y: cardCY + cardHeight / 2)
        .id(stepIndex)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity.combined(with: .scale(scale: 0.95))
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stepIndex)
    }

    // MARK: - Actions

    private func advance() {
        if isLast {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                stepIndex += 1
            }
        }
    }

    private func dismiss() {
        hasSeenQuickstart = true
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }

    private func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(hi, value))
    }
}

// MARK: - Arrow Shape

private struct DownArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 4, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
