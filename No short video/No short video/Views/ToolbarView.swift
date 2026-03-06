//
//  ToolbarView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Modern bottom navigation toolbar with proper contrast in both light and dark mode.
struct ToolbarView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @Binding var showLibrary: Bool
    var onCollapse: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            toolbarButton(icon: "chevron.left", disabled: !viewModel.webViewState.canGoBack) {
                viewModel.goBack()
            }

            toolbarButton(icon: "chevron.right", disabled: !viewModel.webViewState.canGoForward) {
                viewModel.goForward()
            }

            // Save — ALWAYS enabled
            toolbarButton(icon: "bookmark.fill", disabled: false, accent: true) {
                viewModel.saveCurrentVideo()
            }

            // Library
            toolbarButton(icon: "books.vertical", disabled: false) {
                showLibrary = true
            }

            toolbarButton(icon: "arrow.clockwise", disabled: false) {
                viewModel.reload()
            }

            toolbarButton(icon: "house", disabled: false) {
                viewModel.goHome()
            }

            // Minimize — collapse toolbar into a bubble
            toolbarButton(icon: "chevron.down", disabled: false) {
                onCollapse()
            }
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: -3)
        )
    }

    // MARK: - Toolbar Button

    private func toolbarButton(
        icon: String,
        disabled: Bool,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    disabled ? Color(.systemGray3) :
                    accent ? Color.red : Color(.label)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}
