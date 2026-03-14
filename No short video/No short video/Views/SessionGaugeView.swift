//
//  SessionGaugeView.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

/// Vertical session gauge on the left edge.
/// Expanded  → glass pill, vertical fill bar, horizontal countdown.
/// Collapsed → draggable glass circle with progress ring.
///
/// The collapsed pill remembers its last dragged position even after
/// the gauge is expanded then collapsed again.
struct SessionGaugeView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @AppStorage("dailyLimitMinutes") private var dailyLimitMinutes: Int = 60

    @State private var isExpanded = true

    // Persists across expand/collapse cycles (not reset on expand)
    @State     private var pillOffset: CGSize  = .zero
    @GestureState private var pillDrag: CGSize = .zero

    var body: some View {
        Group {
            if isExpanded {
                expandedGauge
            } else {
                collapsedPill
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
    }

    // MARK: - Expanded

    private var expandedGauge: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

            // Vertical fill bar
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fillGradient)
                        .frame(height: max(6, geo.size.height * viewModel.sessionProgress))
                        .animation(.linear(duration: 1), value: viewModel.sessionProgress)
                }
            }
            .frame(width: 7, height: 76)

            // Horizontal countdown label (no rotation)
            Text(countdownLabel)
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 28)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 9)
        .frame(width: 34)
        .background(glassBackground(Capsule()))
        .transition(.scale(scale: 0.5).combined(with: .opacity))
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isExpanded = false }
        }
    }

    // MARK: - Collapsed (draggable, position persists)

    private var collapsedPill: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))

            Circle()
                .trim(from: 0, to: viewModel.sessionProgress)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: viewModel.sessionProgress)
                .padding(4)
        }
        .frame(width: 36, height: 36)
        .shadow(color: gaugeColor.opacity(0.5), radius: 8, x: 2)
        // Apply accumulated drag offset (survives expand ↔ collapse)
        .offset(x: pillOffset.width + pillDrag.width,
                y: pillOffset.height + pillDrag.height)
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($pillDrag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    pillOffset.width  += value.translation.width
                    pillOffset.height += value.translation.height
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isExpanded = true }
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    // MARK: - Helpers

    private var gaugeColor: Color {
        switch viewModel.sessionProgress {
        case ..<0.5: return .green
        case ..<1.0: return .orange
        default:     return .red
        }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(colors: [gaugeColor.opacity(0.5), gaugeColor],
                       startPoint: .bottom, endPoint: .top)
    }

    private var countdownLabel: String {
        let limitSec = Double(dailyLimitMinutes) * 60
        let rem = max(0, limitSec - viewModel.sessionProgress * limitSec)
        return "\(Int(rem / 60))m"
    }

    @ViewBuilder
    private func glassBackground<S: Shape>(_ shape: S) -> some View {
        shape.fill(.ultraThinMaterial)
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.38), gaugeColor.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: gaugeColor.opacity(0.28), radius: 10, x: 3)
    }
}
