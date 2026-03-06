//
//  ContentView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Root view: full‑screen YouTube web view with an adaptive toolbar.
/// iPhone → bottom bar.  iPad / Mac → right‑side bar.
struct ContentView: View {

    @StateObject private var viewModel = YouTubeWebViewModel()
    @State private var showLibrary = false
    @State private var showToolbar = true

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ZStack {
            // Main layout: web view + optional toolbar
            if isCompact {
                // ── iPhone: toolbar at bottom ──
                ZStack(alignment: .bottom) {
                    YouTubeWebView(webView: viewModel.webView)
                    bottomToolbarLayer
                }
            } else {
                // ── iPad / Mac: toolbar at trailing edge ──
                HStack(spacing: 0) {
                    YouTubeWebView(webView: viewModel.webView)
                    trailingToolbarLayer
                }
            }

            // Save feedback toast (always on top)
            if viewModel.showSavedFeedback {
                savedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: viewModel.showSavedFeedback)
            }
        }
        .onAppear {
            viewModel.loadYouTube()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(youtubeVM: viewModel, isPresented: $showLibrary)
        }
        .alert("Save Error", isPresented: $viewModel.showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveErrorMessage)
        }
    }

    // MARK: - Bottom Toolbar (iPhone)

    @ViewBuilder
    private var bottomToolbarLayer: some View {
        if showToolbar {
            VStack(spacing: 0) {
                Spacer()
                ToolbarView(viewModel: viewModel, showLibrary: $showLibrary) {
                    withAnimation(.spring(response: 0.35)) { showToolbar = false }
                    viewModel.setBottomMargin(visible: false)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            collapsedBubble(edge: .bottom)
        }
    }

    // MARK: - Trailing Toolbar (iPad / Mac)

    @ViewBuilder
    private var trailingToolbarLayer: some View {
        if showToolbar {
            ToolbarView(viewModel: viewModel, showLibrary: $showLibrary) {
                withAnimation(.spring(response: 0.35)) { showToolbar = false }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 6)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            collapsedBubble(edge: .trailing)
        }
    }

    // MARK: - Collapsed Bubble

    private func collapsedBubble(edge: Edge) -> some View {
        VStack {
            if edge == .bottom { Spacer() }
            HStack {
                if edge == .trailing || edge == .bottom { Spacer() }
                Button {
                    withAnimation(.spring(response: 0.35)) { showToolbar = true }
                    if isCompact { viewModel.setBottomMargin(visible: true) }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 40))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(.systemGray2))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .padding(edge == .bottom ? .bottom : .trailing, 14)
                .padding(edge == .bottom ? .trailing : .top, 20)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Saved Toast

    private var savedToast: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Saved to Library")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.top, 60)

            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
