//
//  ToolbarView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Adaptive toolbar: horizontal bottom bar on iPhone, vertical right bar on iPad/Mac.
/// Glass styling with per-icon glow, matching and exceeding the SessionGaugeView aesthetic.
struct ToolbarView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @Binding var showLibrary: Bool
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
            toolbarButton(icon: "chevron.left",
                          disabled: !viewModel.webViewState.canGoBack) { viewModel.goBack() }

            toolbarButton(icon: "chevron.right",
                          disabled: !viewModel.webViewState.canGoForward) { viewModel.goForward() }

            toolbarButton(icon: "bookmark.fill",
                          disabled: false, accent: true) { viewModel.saveCurrentVideo() }

            toolbarButton(icon: "books.vertical",
                          disabled: false) { showLibrary = true }

            toolbarButton(icon: "arrow.clockwise",
                          disabled: false) { viewModel.reload() }

            toolbarButton(icon: "house",
                          disabled: false) { onHome() }

            toolbarButton(icon: "gearshape",
                          disabled: false) { onSettings() }

            toolbarButton(icon: isCompact ? "chevron.down" : "chevron.right",
                          disabled: false) { onCollapse() }
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
