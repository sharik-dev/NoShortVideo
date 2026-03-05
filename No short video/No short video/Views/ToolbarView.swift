//
//  ToolbarView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Bottom navigation toolbar with back, forward, reload, and home buttons.
struct ToolbarView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel

    var body: some View {
        HStack {
            Spacer()

            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            .disabled(!viewModel.webViewState.canGoBack)

            Spacer()

            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
            .disabled(!viewModel.webViewState.canGoForward)

            Spacer()

            Button(action: { viewModel.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
            }

            Spacer()

            Button(action: { viewModel.goHome() }) {
                Image(systemName: "house")
                    .font(.title2)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
