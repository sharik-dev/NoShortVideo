//
//  UsageStatsView.swift
//  No short video
//

import Charts
import SwiftUI

/// Temps passé sur chaque site : aujourd'hui, sur 7 jours ou sur 30 jours.
struct UsageStatsView: View {

    @ObservedObject private var store = SiteUsageStore.shared
    @AppStorage("appLanguage") private var lang: String = "en"
    @Environment(\.dismiss) private var dismiss

    private enum Period: Int, CaseIterable {
        case today = 1, week = 7, month = 30
    }

    @State private var period: Period = .today

    /// Même rouge que les tuiles de l'accueil.
    private let accent = Color(red: 1, green: 0, blue: 0)

    private var days: [Date] { SiteUsageStore.lastDays(period.rawValue) }

    private var rows: [(site: UsageSite, seconds: Double, opens: Int)] {
        UsageSite.allCases
            .map { ($0, store.seconds(site: $0, days: days), store.opens(site: $0, days: days)) }
            .filter { $0.1 > 0 || $0.2 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private var total: Double { rows.reduce(0) { $0 + $1.seconds } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("", selection: $period) {
                        Text(t("Aujourd'hui", "Today")).tag(Period.today)
                        Text(t("7 jours", "7 days")).tag(Period.week)
                        Text(t("30 jours", "30 days")).tag(Period.month)
                    }
                    .pickerStyle(.segmented)

                    summary

                    if period != .today { chart }

                    siteList
                }
                .padding(20)
            }
            .navigationTitle(t("Statistiques", "Statistics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("OK", "Done")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { store.persist() }
    }

    // MARK: - Résumé

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(periodLabel)
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
            Text(SiteUsageStore.format(total))
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
            if period != .today {
                Text(t("≈ \(SiteUsageStore.format(total / Double(period.rawValue))) par jour",
                       "≈ \(SiteUsageStore.format(total / Double(period.rawValue))) per day"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var periodLabel: String {
        switch period {
        case .today: return t("Temps passé aujourd'hui", "Time spent today")
        case .week:  return t("Temps passé sur 7 jours", "Time spent in the last 7 days")
        case .month: return t("Temps passé sur 30 jours", "Time spent in the last 30 days")
        }
    }

    // MARK: - Graphique

    private var chart: some View {
        Chart(days, id: \.self) { day in
            BarMark(
                x: .value("Day", day, unit: .day),
                y: .value("Minutes", store.seconds(on: day) / 60)
            )
            .foregroundStyle(accent.gradient)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let m = value.as(Double.self) { Text("\(Int(m))m") } }
            }
        }
        .chartXAxis {
            if period == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            }
        }
        .frame(height: 160)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Par site

    @ViewBuilder
    private var siteList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Par site", "By site"))
                .font(.footnote.bold())
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text(t("Aucune utilisation sur cette période.", "No usage in this period."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                let maxSeconds = rows.first?.seconds ?? 1
                ForEach(rows, id: \.site) { row in
                    siteRow(row.site, seconds: row.seconds, opens: row.opens, max: maxSeconds)
                }
            }
        }
    }

    private func siteRow(_ site: UsageSite, seconds: Double, opens: Int, max: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: site.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(site.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(SiteUsageStore.format(seconds))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(accent.gradient)
                            .frame(width: max > 0 ? geo.size.width * seconds / max : 0)
                    }
                }
                .frame(height: 6)
                HStack {
                    if opens > 0 {
                        Text(t("\(opens) ouverture\(opens > 1 ? "s" : "")",
                               "\(opens) open\(opens == 1 ? "" : "s")"))
                    }
                    Spacer()
                    if total > 0 {
                        Text("\(Int((seconds / total * 100).rounded())) %")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }
}

#Preview { UsageStatsView() }
