//
//  SettingsView.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

struct SettingsView: View {

    @AppStorage("dailyLimitMinutes")    private var dailyLimitMinutes: Int  = 60
    @AppStorage("gaugeEnabled")         private var gaugeEnabled: Bool      = false
    @AppStorage("statsEnabled")         private var statsEnabled: Bool      = false
    @AppStorage("blockOnLimit")         private var blockOnLimit: Bool      = false
    @AppStorage("hideRecommendations")  private var hideRecommendations: Bool = false
    @AppStorage("blurThumbnails")       private var blurThumbnails: Bool    = false
    @AppStorage("grayscaleMode")        private var grayscaleMode: Bool     = false
    @AppStorage("adBlockEnabled")       private var adBlockEnabled: Bool    = true
    @AppStorage("appLanguage")          private var lang: String            = "en"
    @AppStorage(HomeCatView.enabledKey) private var catEnabled: Bool        = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {

                // ── Language ──
                Section {
                    Picker(t("Langue", "Language"), selection: $lang) {
                        Text("English").tag("en")
                        Text("Français").tag("fr")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(t("Langue", "Language"))
                }

                // ── Compagnon ──
                Section {
                    Toggle(isOn: $catEnabled) {
                        Label(t("Chat sur l'accueil", "Cat on the home screen"),
                              systemImage: "cat.fill")
                    }
                } header: {
                    Text(t("Compagnon", "Companion"))
                } footer: {
                    Text(t(
                        "Il s'endort de plus en plus à mesure que tu approches ta limite du jour.",
                        "It gets sleepier as you get closer to your daily limit."
                    ))
                    + Text(verbatim: "\n\n")
                    // Crédit exigé par la licence CC BY du modèle 3D.
                    + Text(t("Chat : « Somali Cat Animated » par DreamNoms (CC BY 4.0).",
                             "Cat: “Somali Cat Animated” by DreamNoms (CC BY 4.0)."))
                }

                // ── Concentration ──
                Section {
                    Toggle(isOn: $hideRecommendations) {
                        Label(t("Cacher les recommandations", "Hide recommendations"),
                              systemImage: "rectangle.slash")
                    }
                    Toggle(isOn: $blurThumbnails) {
                        Label(t("Flouter les miniatures", "Blur thumbnails"),
                              systemImage: "circle.dotted")
                    }
                    Toggle(isOn: $grayscaleMode) {
                        Label(t("Mode noir et blanc", "Grayscale mode"),
                              systemImage: "circle.lefthalf.filled")
                    }
                } header: {
                    Text(t("Concentration", "Focus"))
                } footer: {
                    Text(t(
                        "Réduit les éléments conçus pour capter l'attention et limiter la dopamine.",
                        "Reduces attention-capturing elements to limit dopamine triggers."
                    ))
                }

                // ── Bloqueur de pub ──
                Section {
                    Toggle(isOn: $adBlockEnabled) {
                        Label(t("Bloqueur de publicité", "Ad blocker"),
                              systemImage: "shield.lefthalf.filled")
                    }
                } header: {
                    Text(t("Publicité", "Advertising"))
                } footer: {
                    Text(t(
                        "Bloque les régies publicitaires avant le chargement, sur tous les sites. Les flux vidéo et la connexion Google ne sont jamais bloqués.",
                        "Blocks ad networks before they load, on every site. Video streams and Google sign-in are never blocked."
                    ))
                }

                // ── Gauge ──
                Section {
                    Toggle(t("Afficher la jauge", "Show session gauge"), isOn: $gaugeEnabled)
                } footer: {
                    Text(t(
                        "La jauge apparaît à gauche et indique le temps restant.",
                        "The gauge appears on the left and shows remaining time."
                    ))
                }

                // ── Live stats ──
                Section {
                    Toggle(isOn: $statsEnabled) {
                        Label(t("Statistiques en direct", "Live stats"),
                              systemImage: "chart.bar.fill")
                    }
                } footer: {
                    Text(t(
                        "Affiche en direct le nombre de vidéos vues et le temps passé sur l'app aujourd'hui.",
                        "Shows a live count of videos watched and time spent on the app today."
                    ))
                }

                // ── Daily limit ──
                Section {
                    Stepper(
                        t("Limite : \(formattedLimit)", "Limit: \(formattedLimit)"),
                        value: $dailyLimitMinutes,
                        in: 5...480,
                        step: 5
                    )
                } header: {
                    Text(t("Limite journalière", "Daily limit"))
                } footer: {
                    Text(t(
                        "La jauge se remplit selon cette durée (défaut : 60 min).",
                        "The gauge fills over this duration (default: 60 min)."
                    ))
                }
                .disabled(!gaugeEnabled)

                // ── Block on limit ──
                Section {
                    Toggle(t("Bloquer à la limite", "Block when limit is reached"), isOn: $blockOnLimit)
                } footer: {
                    Text(t(
                        "YouTube sera verrouillé quand la limite de session est atteinte.",
                        "YouTube will be locked when the session limit is reached."
                    ))
                }
                .disabled(!gaugeEnabled)

                // ── Colour legend ──
                Section {
                    row(.green,  t("Vert", "Green"),    "< \(dailyLimitMinutes / 2) min")
                    row(.orange, t("Orange", "Orange"), "\(dailyLimitMinutes / 2)–\(dailyLimitMinutes) min")
                    row(.red,    t("Rouge", "Red"),     "> \(dailyLimitMinutes) min")
                } header: {
                    Text(t("Couleurs de la jauge", "Gauge colours"))
                }
                .disabled(!gaugeEnabled)
            }
            .navigationTitle(t("Paramètres", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Fermer", "Close")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    @ViewBuilder
    private func row(_ color: Color, _ label: String, _ detail: String) -> some View {
        HStack {
            Label(label, systemImage: "circle.fill").foregroundStyle(color)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var formattedLimit: String {
        if dailyLimitMinutes >= 60 {
            let h = dailyLimitMinutes / 60
            let m = dailyLimitMinutes % 60
            return m == 0 ? "\(h)h" : "\(h)h\(m)"
        }
        return "\(dailyLimitMinutes) min"
    }
}

#Preview { SettingsView() }
