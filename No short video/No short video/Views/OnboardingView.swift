//
//  OnboardingView.swift
//  No short video
//

import SwiftUI

// MARK: - Model

private struct OnboardingSlide {
    let icon: String
    let iconColor: Color
    let title: String
    let titleFR: String
    let body: String
    let bodyFR: String
}

private let slides: [OnboardingSlide] = [
    OnboardingSlide(
        icon: "hand.raised.slash.fill",
        iconColor: .red,
        title: "No Short Video",
        titleFR: "No Short Video",
        body: "YouTube the way you want it.\nLong-form content only — no distractions.",
        bodyFR: "YouTube comme vous le voulez.\nUniquement du contenu long, sans distractions."
    ),
    OnboardingSlide(
        icon: "timer",
        iconColor: .orange,
        title: "Control Your Time",
        titleFR: "Maîtrisez votre temps",
        body: "Set a daily limit and watch the gauge count down. Enable Step Mode to earn watch time by walking.",
        bodyFR: "Fixez une limite quotidienne et suivez votre session. Activez le mode pas pour gagner du temps en marchant."
    ),
    OnboardingSlide(
        icon: "bookmark.fill",
        iconColor: Color(red: 0.2, green: 0.5, blue: 1.0),
        title: "Save What Matters",
        titleFR: "Sauvegardez l'essentiel",
        body: "Bookmark any video in one tap and find it in your library whenever you're ready to watch.",
        bodyFR: "Marquez n'importe quelle vidéo d'un tap et retrouvez-la dans votre bibliothèque quand vous voulez."
    ),
]

// MARK: - Main View

struct OnboardingView: View {

    var onComplete: () -> Void

    @AppStorage("appLanguage") private var lang: String = "en"
    @State private var page = 0

    private func t(_ en: String, _ fr: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                skipButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                    .padding(.top, 60)

                slideCarousel
                    .layoutPriority(1)

                pageIndicator
                    .padding(.bottom, 28)

                actionButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [slides[page].iconColor.opacity(0.18), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: page)
        }
    }

    // MARK: - Skip

    private var skipButton: some View {
        Button {
            onComplete()
        } label: {
            Text(t("Skip", "Passer"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .opacity(page < slides.count - 1 ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    // MARK: - Slide Carousel

    private var slideCarousel: some View {
        TabView(selection: $page) {
            ForEach(Array(slides.enumerated()), id: \.offset) { i, slide in
                SlideView(slide: slide, lang: lang)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule()
                    .fill(page == i ? .white : .white.opacity(0.25))
                    .frame(width: page == i ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
            }
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        let isLast = page == slides.count - 1
        let label = isLast
            ? t("Get Started →", "Commencer →")
            : t("Continue", "Continuer")

        return Button {
            if isLast {
                onComplete()
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { page += 1 }
            }
        } label: {
            Text(label)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .white.opacity(0.2), radius: 20, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(1)
        .animation(.spring(response: 0.3), value: page)
    }
}

// MARK: - Slide View

private struct SlideView: View {
    let slide: OnboardingSlide
    let lang: String

    private func t(_ en: String, _ fr: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with glow
            ZStack {
                Circle()
                    .fill(slide.iconColor.opacity(0.2))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)

                Circle()
                    .fill(slide.iconColor.opacity(0.1))
                    .frame(width: 110, height: 110)

                Image(systemName: slide.icon)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(slide.iconColor)
                    .shadow(color: slide.iconColor.opacity(0.6), radius: 16)
                    .shadow(color: slide.iconColor.opacity(0.3), radius: 32)
            }
            .padding(.bottom, 52)

            // Title
            Text(t(slide.title, slide.titleFR))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Body
            Text(t(slide.body, slide.bodyFR))
                .font(.body)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .padding(.top, 18)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
    }
}
