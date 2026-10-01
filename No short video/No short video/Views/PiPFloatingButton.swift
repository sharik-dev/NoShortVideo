//
//  PiPFloatingButton.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

/// Draggable floating PiP button, glass-styled to match the toolbar.
struct PiPFloatingButton: View {

    @ObservedObject var viewModel: YouTubeWebViewModel

    @State private var btnOffset: CGSize = .zero

    var body: some View {
        Image(systemName: "pip.enter")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color(.label))
            .frame(width: 38, height: 38)
            .background(glassBackground)
            .contentShape(Rectangle())
            .floatingDrag(offset: $btnOffset) { viewModel.triggerPiP() }
    }

    // Glass background matching toolbar style
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.38), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
}
