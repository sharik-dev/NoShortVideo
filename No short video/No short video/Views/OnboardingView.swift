//
//  OnboardingView.swift
//  No short video
//
//  Sept écrans, un par fonction phare. Chacun montre une **vraie capture** de
//  l'app (dans la langue de l'utilisateur), un projecteur sur l'élément à
//  toucher, une annotation courte, et une seule phrase en dessous.
//
//  Les captures sortent de l'app elle-même, pas d'une maquette : seules les
//  miniatures et les titres des vidéos sont remplacés par des chats, en clin
//  d'œil (cf. `CaptureScriptService`). Si l'interface change, on les refait —
//  sinon l'onboarding montre une app qui n'existe plus.
//
//  Exception : écran verrouillé et PiP. Le simulateur ne sait faire ni l'un
//  ni l'autre avec WebKit ; le fond est une vraie capture système, le lecteur
//  et la fenêtre PiP d'iOS sont reconstitués par-dessus
//  (onboarding-captures/compose_system.py).
//
//  Images : `onb_<écran>_<en|fr>` dans Assets.xcassets.
//  Zones : coordonnées normalisées (0…1) dans la capture.
//

import SwiftUI

// MARK: - Model

private struct OnboardingSlide {
    let image: String
    /// Zone mise en lumière, en fraction de la capture.
    let spot: CGRect
    /// Rayon du projecteur, en fraction de la largeur de la capture.
    let spotRadius: CGFloat
    /// L'annotation se place au-dessus ou en dessous du projecteur.
    let calloutAbove: Bool
    let calloutIcon: String
    let callout: (en: String, fr: String)
    let sentence: (en: String, fr: String)
}

private let slides: [OnboardingSlide] = [
    OnboardingSlide(
        image: "onb_home",
        spot: CGRect(x: 0.06, y: 0.26, width: 0.88, height: 0.28),
        spotRadius: 0.06,
        calloutAbove: false,
        calloutIcon: "hand.raised.slash.fill",
        callout: ("No Shorts, anywhere", "Zéro Shorts, partout"),
        sentence: ("Your usual sites, minus the short videos.",
                   "Tes sites habituels, sans les vidéos courtes.")
    ),
    OnboardingSlide(
        image: "onb_watch",
        spot: CGRect(x: 0.0, y: 0.125, width: 1.0, height: 0.26),
        spotRadius: 0.02,
        calloutAbove: false,
        calloutIcon: "checkmark.shield.fill",
        callout: ("0 ads", "0 pub"),
        sentence: ("Videos start right away. No ads, ever.",
                   "Les vidéos démarrent direct. Jamais de pub.")
    ),
    OnboardingSlide(
        image: "onb_music",
        spot: CGRect(x: 0.03, y: 0.605, width: 0.94, height: 0.225),
        spotRadius: 0.05,
        calloutAbove: true,
        calloutIcon: "music.note",
        callout: ("Music, zero ads", "Musique, zéro pub"),
        sentence: ("YouTube Music plays straight through. No ads.",
                   "YouTube Music s'enchaîne sans coupure. Zéro pub.")
    ),
    OnboardingSlide(
        image: "onb_syslock",
        spot: CGRect(x: 0.035, y: 0.627, width: 0.93, height: 0.204),
        spotRadius: 0.085,
        calloutAbove: true,
        calloutIcon: "lock.fill",
        callout: ("Plays with the app closed", "Joue même app fermée"),
        sentence: ("Close the app or lock your phone: the music keeps going.",
                   "Ferme l'app ou verrouille : la musique continue.")
    ),
    OnboardingSlide(
        image: "onb_syspip",
        spot: CGRect(x: 0.373, y: 0.60, width: 0.592, height: 0.153),
        spotRadius: 0.042,
        calloutAbove: true,
        calloutIcon: "pip.fill",
        callout: ("Picture in Picture", "Image dans l'image"),
        sentence: ("Keep watching in a floating window, over your other apps.",
                   "Continue de regarder en fenêtre flottante, par-dessus tes apps.")
    ),
    OnboardingSlide(
        image: "onb_library",
        spot: CGRect(x: 0.025, y: 0.225, width: 0.95, height: 0.105),
        spotRadius: 0.04,
        calloutAbove: false,
        calloutIcon: "bookmark.fill",
        callout: ("Your favourites", "Tes favoris"),
        sentence: ("Everything you save waits for you in Library.",
                   "Tout ce que tu gardes t'attend dans la Librairie.")
    ),
]

private let appRed = Color(red: 1, green: 0, blue: 0)

/// Proportions des captures (iPhone 17, 1206 × 2622).
private let shotAspect: CGFloat = 1206.0 / 2622.0

// MARK: - Main View

struct OnboardingView: View {

    var onComplete: () -> Void

    @AppStorage("appLanguage") private var lang: String = "en"
    @State private var page = 0

    private func t(_ en: String, _ fr: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [appRed.opacity(0.16), .clear],
                           center: .bottom, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                skipButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                    .frame(height: 36)

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { i, slide in
                        SlideView(slide: slide, lang: lang, isActive: page == i)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                actionButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .onAppear {
            // `-debugOnboardingPage 3` ouvre directement le 4ᵉ écran (captures).
            let p = UserDefaults.standard.integer(forKey: "debugOnboardingPage")
            if slides.indices.contains(p), p > 0 { page = p }
        }
        #endif
    }

    private var skipButton: some View {
        Button(action: onComplete) {
            Text(t("Skip", "Passer"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .opacity(page < slides.count - 1 ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule()
                    .fill(page == i ? appRed : .white.opacity(0.25))
                    .frame(width: page == i ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
            }
        }
    }

    private var actionButton: some View {
        let isLast = page == slides.count - 1
        return Button {
            if isLast {
                onComplete()
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { page += 1 }
            }
        } label: {
            Text(isLast ? t("Get Started", "Commencer") : t("Continue", "Continuer"))
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slide

private struct SlideView: View {
    let slide: OnboardingSlide
    let lang: String
    let isActive: Bool

    /// Le projecteur s'allume un instant après l'arrivée sur l'écran : on voit
    /// d'abord la capture entière, puis ce qu'il faut regarder.
    @State private var lit = false

    private func t(_ pair: (en: String, fr: String)) -> String { lang == "fr" ? pair.fr : pair.en }

    var body: some View {
        VStack(spacing: 22) {
            GeometryReader { geo in
                let h = geo.size.height
                let w = min(geo.size.width - 64, h * shotAspect)
                let size = CGSize(width: w, height: w / shotAspect)

                PhoneShot(slide: slide, lang: lang, size: size, lit: lit, callout: t(slide.callout))
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            Text(t(slide.sentence))
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
        .onChange(of: isActive, initial: true) { _, active in
            lit = false
            guard active else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { lit = true }
            }
        }
    }
}

// MARK: - Phone + capture + projecteur

private struct PhoneShot: View {
    let slide: OnboardingSlide
    let lang: String
    let size: CGSize
    let lit: Bool
    let callout: String

    private var corner: CGFloat { size.width * 0.13 }

    private var spotRect: CGRect {
        CGRect(x: slide.spot.minX * size.width,
               y: slide.spot.minY * size.height,
               width: slide.spot.width * size.width,
               height: slide.spot.height * size.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("\(slide.image)_\(lang == "fr" ? "fr" : "en")")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)

            dimmer
            ring
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: corner + 5, style: .continuous)
                .fill(Color(white: 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner + 5, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        // L'annotation peut déborder du téléphone : elle vit hors du clip.
        .overlay(alignment: .topLeading) { calloutView.offset(x: 5, y: 5) }
        .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
    }

    /// Voile sombre percé à l'endroit de la fonction.
    private var dimmer: some View {
        let r = slide.spotRadius * size.width
        return Rectangle()
            .fill(.black.opacity(lit ? 0.58 : 0))
            .mask {
                ZStack {
                    Rectangle()
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .frame(width: spotRect.width, height: spotRect.height)
                        .position(x: spotRect.midX, y: spotRect.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    private var ring: some View {
        let r = slide.spotRadius * size.width
        return TimelineView(.animation(paused: !lit)) { tl in
            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            ZStack {
                RoundedRectangle(cornerRadius: r + 6 * p, style: .continuous)
                    .stroke(appRed.opacity(0.7 * (1 - p)), lineWidth: 2)
                    .frame(width: spotRect.width + 14 * p, height: spotRect.height + 14 * p)
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(appRed, lineWidth: 2.5)
                    .frame(width: spotRect.width, height: spotRect.height)
                    .shadow(color: appRed.opacity(0.9), radius: 8)
            }
            .position(x: spotRect.midX, y: spotRect.midY)
        }
        .opacity(lit ? 1 : 0)
        .scaleEffect(lit ? 1 : 1.15, anchor: UnitPoint(x: spotRect.midX / size.width,
                                                     y: spotRect.midY / size.height))
        .allowsHitTesting(false)
    }

    /// Pastille rouge reliée au projecteur par un trait.
    private var calloutView: some View {
        // Pastille (~33 pt) + trait (14 pt) : le centre est à ~24 pt du bord.
        let gap: CGFloat = 4
        let anchorY = slide.calloutAbove ? spotRect.minY - gap : spotRect.maxY + gap
        let x = min(max(spotRect.midX, 90), size.width - 90)

        return VStack(spacing: 0) {
            if !slide.calloutAbove { connector }
            HStack(spacing: 6) {
                Image(systemName: slide.calloutIcon)
                    .font(.system(size: 12, weight: .bold))
                Text(callout)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(appRed))
            .shadow(color: appRed.opacity(0.6), radius: 12)
            if slide.calloutAbove { connector }
        }
        .fixedSize()
        .position(x: x, y: anchorY + (slide.calloutAbove ? -24 : 24))
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(lit ? 1 : 0)
        .offset(y: lit ? 0 : (slide.calloutAbove ? 8 : -8))
        .allowsHitTesting(false)
    }

    private var connector: some View {
        Rectangle()
            .fill(appRed)
            .frame(width: 2, height: 14)
    }
}

#Preview {
    OnboardingView {}
}
