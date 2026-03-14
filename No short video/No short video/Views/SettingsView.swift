//
//  SettingsView.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

struct SettingsView: View {

    @AppStorage("dailyLimitMinutes") private var dailyLimitMinutes: Int = 60
    @AppStorage("gaugeEnabled")      private var gaugeEnabled: Bool     = true
    @AppStorage("appLanguage")       private var lang: String           = "en"

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

                // ── Gauge ──
                Section {
                    Toggle(t("Afficher la jauge", "Show session gauge"), isOn: $gaugeEnabled)
                } footer: {
                    Text(t(
                        "La jauge apparaît à gauche et indique le temps restant.",
                        "The gauge appears on the left and shows remaining time."
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
