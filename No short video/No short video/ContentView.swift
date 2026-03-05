//
//  ContentView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Root view: full‑screen YouTube web view with a modern bottom toolbar.
struct ContentView: View {

    @StateObject private var viewModel = YouTubeWebViewModel()
    @State private var showLibrary = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Web view — respects notch
            YouTubeWebView(webView: viewModel.webView)

            // Bottom toolbar
            VStack(spacing: 0) {
                Spacer()

                ToolbarView(viewModel: viewModel, showLibrary: $showLibrary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            // Save feedback toast
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
