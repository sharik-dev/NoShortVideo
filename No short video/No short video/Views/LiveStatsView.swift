//
//  LiveStatsView.swift
//  No short video
//
//  Created by Sharik Mohamed on 01/07/2026.
//

import SwiftUI

/// Small draggable glass pill showing live daily usage:
/// videos watched today and time spent on the app today.
struct LiveStatsView: View {

    @ObservedObject private var stats = DailyStatsStore.shared
    @AppStorage("appLanguage") private var lang: String = "en"

    // Draggable position, guarded so a drag never fires the (unused) tap.
    @State     private var offset: CGSize  = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        HStack(spacing: 14) {
            metric(icon: "play.rectangle.fill",
                   value: "\(stats.videosWatchedToday)",
                   label: t("vidéos", "videos"))

            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.18))

            metric(icon: "clock.fill",
                   value: stats.formattedTimeOnApp,
                   label: t("aujourd'hui", "today"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(glassBackground)
        .offset(x: offset.width + drag.width,
                y: offset.height + drag.height)
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($drag) { v, s, _ in s = v.translation }
                .onEnded { v in
                    offset.width  += v.translation.width
                    offset.height += v.translation.height
                }
        )
    }

    // MARK: - Metric cell

    @ViewBuilder
    private func metric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Style

    private var glassBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().stroke(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }
}
