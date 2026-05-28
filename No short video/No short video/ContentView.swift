//
//  ContentView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var viewModel   = YouTubeWebViewModel()
    @State private var showLibrary       = false
    @State private var showToolbar       = true
    @State private var showSettings      = false
    @State private var showHome          = false  // set by onAppear based on onboarding state

    @AppStorage("gaugeEnabled")          private var gaugeEnabled: Bool    = true
    @AppStorage("appLanguage")           private var lang: String          = "en"
    @AppStorage("stepModeEnabled")       private var stepModeEnabled: Bool = false
    @AppStorage("hasSeenOnboarding")     private var hasSeenOnboarding: Bool = false
    @AppStorage("hasSeenQuickstart")     private var hasSeenQuickstart: Bool = false

    @State private var showOnboarding    = false
    @State private var showQuickstart    = false

    // Draggable collapsed toolbar bubble
    @State     private var bubbleOffset: CGSize  = .zero
    @GestureState private var bubbleDrag: CGSize = .zero
    // Tracks whether a drag is in progress — prevents the tap from firing on drag release
    @State private var bubbleDragActive: Bool    = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ZStack {
            if isCompact {
                ZStack(alignment: .bottom) {
                    YouTubeWebView(webView: viewModel.webView)
                    bottomToolbarLayer
                }
                .overlay(alignment: .leading) {
                    VStack(spacing: 14) {
                        Spacer()
                        if gaugeEnabled {
                            SessionGaugeView(viewModel: viewModel)
                        }
                        PiPFloatingButton(viewModel: viewModel)
                        Spacer().frame(height: 84)
                    }
                    .padding(.leading, 6)
                }
            } else {
                HStack(spacing: 0) {
                    YouTubeWebView(webView: viewModel.webView)
                    trailingToolbarLayer
                }
            }

            if viewModel.showSavedFeedback {
                savedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: viewModel.showSavedFeedback)
            }

            if viewModel.isBlocked {
                if stepModeEnabled {
                    StepBlockOverlayView(viewModel: viewModel, showSettings: $showSettings)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.isBlocked)
                } else {
                    blockedOverlay
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.isBlocked)
                }
            }
        }
        .overlayPreferenceValue(CoachMarkBoundsKey.self) { anchors in
            if showQuickstart {
                QuickstartOverlay(isPresented: $showQuickstart, anchors: anchors)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showQuickstart)
            }
        }
        .onAppear {
            viewModel.loadYouTube()
            if !hasSeenOnboarding {
                showOnboarding = true
            } else {
                showHome = true
                if !hasSeenQuickstart {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        showQuickstart = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
                if !hasSeenQuickstart {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        showQuickstart = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showHome) {
            BrowserHomeView(viewModel: viewModel, isPresented: $showHome)
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(youtubeVM: viewModel, isPresented: $showLibrary)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert(t("Erreur de sauvegarde", "Save Error"),
               isPresented: $viewModel.showSaveError) {
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
                ToolbarView(
                    viewModel:   viewModel,
                    showLibrary: $showLibrary,
                    onCollapse: {
                        withAnimation(.spring(response: 0.35)) { showToolbar = false }
                        viewModel.setBottomMargin(visible: false)
                    },
                    onHome:     { showHome     = true },
                    onSettings: { showSettings = true }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            draggableBubble
        }
    }

    // MARK: - Draggable collapsed bubble
    // Uses .onTapGesture + DragGesture with a guard flag so a drag-release
    // never accidentally re-opens the toolbar.

    private var draggableBubble: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .ultraThinMaterial)
                    .shadow(color: .white.opacity(0.25), radius: 12)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: bubbleOffset.width + bubbleDrag.width,
                            y: bubbleOffset.height + bubbleDrag.height)
                    // Tap: only expand if no drag occurred
                    .onTapGesture {
                        guard !bubbleDragActive else { return }
                        withAnimation(.spring(response: 0.35)) { showToolbar = true }
                        viewModel.setBottomMargin(visible: true)
                    }
                    // Drag: accumulate offset, set flag so tap is ignored
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in bubbleDragActive = true }
                            .updating($bubbleDrag) { v, s, _ in s = v.translation }
                            .onEnded { v in
                                bubbleOffset.width  += v.translation.width
                                bubbleOffset.height += v.translation.height
                                // Reset after the tap recognizer has already fired
                                DispatchQueue.main.async { bubbleDragActive = false }
                            }
                    )
                    .padding(.bottom, 18)
                    .padding(.trailing, 18)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Trailing Toolbar (iPad / Mac)

    @ViewBuilder
    private var trailingToolbarLayer: some View {
        if showToolbar {
            ToolbarView(
                viewModel:   viewModel,
                showLibrary: $showLibrary,
                onCollapse:  { withAnimation(.spring(response: 0.35)) { showToolbar = false } },
                onHome:      { showHome     = true },
                onSettings:  { showSettings = true }
            )
            .padding(.vertical, 12)
            .padding(.trailing, 6)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            VStack {
                Button {
                    withAnimation(.spring(response: 0.35)) { showToolbar = true }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 40))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(.systemGray2))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .padding(.top, 20).padding(.trailing, 14)
                Spacer()
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Saved Toast

    private var savedToast: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(t("Sauvegardé", "Saved to Library"))
                    .font(.subheadline).fontWeight(.semibold)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Blocked Overlay

    private var blockedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "timer")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text(t("Limite atteinte", "Limit reached"))
                        .font(.title2.bold())
                    Text(t(
                        "Tu as utilisé ton temps YouTube pour cette session.\nAugmente la limite dans les paramètres pour continuer.",
                        "You've used your YouTube time for this session.\nIncrease the limit in settings to continue."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                Button {
                    showSettings = true
                } label: {
                    Label(t("Paramètres", "Settings"), systemImage: "gearshape")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(.top, 4)
            }
        }
    }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }
}

#Preview { ContentView() }
