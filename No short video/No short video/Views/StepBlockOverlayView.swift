//
//  StepBlockOverlayView.swift
//  No short video
//

import SwiftUI

struct StepBlockOverlayView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @Binding var showSettings: Bool

    @AppStorage("appLanguage")    private var lang: String = "en"
    @AppStorage("stepsPerMinute") private var stepsPerMinute: Int = 100

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // ── Icône animée ──
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                    Image(systemName: "figure.walk")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(.orange)
                }

                // ── Titre ──
                VStack(spacing: 8) {
                    Text(t("Marchez pour débloquer", "Walk to unlock"))
                        .font(.title2.bold())
                    Text(t(
                        "Votre temps est épuisé. Marchez pour en gagner davantage !",
                        "You've run out of time. Walk to earn more!"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                // ── Compteur de pas live ──
                VStack(spacing: 6) {
                    Text(t("Pas aujourd'hui", "Steps today"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(viewModel.stepModeSteps)")
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(response: 0.35), value: viewModel.stepModeSteps)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 40)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                // ── Progression vers la prochaine minute ──
                VStack(spacing: 8) {
                    let spm = stepsPerMinute > 0 ? stepsPerMinute : 100
                    let stepsInCurrentMinute = viewModel.stepModeSteps % spm
                    let remaining = spm - stepsInCurrentMinute
                    let progress = Double(stepsInCurrentMinute) / Double(spm)

                    Text(t(
                        "Encore \(remaining) pas pour 1 minute",
                        "\(remaining) more steps for 1 minute"
                    ))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.2))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * progress, height: 8)
                                .animation(.linear(duration: 0.4), value: progress)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, 40)
                }
            }

            // ── Bouton Paramètres discret ──
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
                Spacer()
            }
        }
        .onAppear { pulseScale = 1.12 }
    }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }
}
