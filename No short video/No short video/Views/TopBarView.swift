//
//  TopBarView.swift
//  No short video
//
//  Created by Sharik Mohamed on 13/03/2026.
//

import SwiftUI

// MARK: - TopBarView

/// Barre supérieure repliable : recherche YouTube, jauge de temps de session, ticker bienveillant.
struct TopBarView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @Binding var isVisible: Bool

    @AppStorage("dailyLimitMinutes") private var dailyLimitMinutes: Int = 60

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Ligne 1 : champ de recherche + bouton replier ──
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Rechercher sur YouTube…", text: $searchText)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            viewModel.search(searchText)
                            isSearchFocused = false
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

                // Bouton replier
                Button {
                    isSearchFocused = false
                    withAnimation(.spring(response: 0.35)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider().opacity(0.4)

            // ── Ligne 2 : jauge de session ──
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Temps sur l'app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sessionLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(gaugeColor)
                    Text("/ \(dailyLimitMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Barre de progression
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 7)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(gaugeColor.gradient)
                            .frame(width: max(7, geo.size.width * viewModel.sessionProgress), height: 7)
                            .animation(.linear(duration: 0.9), value: viewModel.sessionProgress)
                    }
                }
                .frame(height: 7)

                // Légende
                HStack(spacing: 10) {
                    legendDot(.green, "< \(dailyLimitMinutes / 2) min")
                    legendDot(.orange, "\(dailyLimitMinutes / 2)–\(dailyLimitMinutes) min")
                    legendDot(.red, "> \(dailyLimitMinutes) min")
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider().opacity(0.4)

            // ── Ligne 3 : ticker bienveillant ──
            MarqueeTextView(
                text: "N'oublie pas ce que tu es venu regarder  •  " +
                      "Pars quand c'est bon  •  " +
                      "Tu contrôles ton écran  •  " +
                      "Le temps est précieux  •  "
            )
            .frame(height: 18)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var sessionLabel: String {
        let limitSeconds = Double(dailyLimitMinutes) * 60
        let seconds = Int(viewModel.sessionProgress * limitSeconds)
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private var gaugeColor: Color {
        let p = viewModel.sessionProgress
        if p < 0.5 { return .green }
        if p < 1.0 { return .orange }
        return .red
    }

    @ViewBuilder
    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - MarqueeTextView

/// Texte défilant horizontalement à l'infini.
private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct MarqueeTextView: View {

    let text: String
    var speed: Double = 48 // points / seconde

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            // Vue de mesure (invisible)
            Text(text)
                .font(.caption2)
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { g in
                        Color.clear
                            .preference(key: TextWidthKey.self, value: g.size.width)
                    }
                )

            // Trois copies pour un défilement sans couture
            HStack(spacing: 0) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .fixedSize()
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .fixedSize()
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .fixedSize()
            }
            .offset(x: offset)
        }
        .clipped()
        .onPreferenceChange(TextWidthKey.self) { w in
            guard w > 0, textWidth == 0 else { return }
            textWidth = w
            let duration = Double(w) / speed
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -w
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var vm = YouTubeWebViewModel()
        @State var visible = true
        var body: some View {
            VStack {
                TopBarView(viewModel: vm, isVisible: $visible)
                Spacer()
            }
            .background(Color(.systemBackground))
        }
    }
    return PreviewWrapper()
}
