//
//  ContentView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Root view: full‑screen YouTube web view with a bottom toolbar.
struct ContentView: View {

    @StateObject private var viewModel = YouTubeWebViewModel()

    var body: some View {
        VStack(spacing: 0) {
            YouTubeWebView(webView: viewModel.webView)
                .ignoresSafeArea(edges: .top)

            ToolbarView(viewModel: viewModel)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .padding(.top, 4)
        .onAppear {
            viewModel.loadYouTube()
        }
    }
}

#Preview {
    ContentView()
}
