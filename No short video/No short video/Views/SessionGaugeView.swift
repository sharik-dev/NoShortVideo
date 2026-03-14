//
//  SessionGaugeView.swift
//  No short video
//
//  Created by Sharik Mohamed on 14/03/2026.
//

import SwiftUI

/// Vertical session gauge — draggable in both expanded and collapsed states.
/// Position is shared between states: dragging while expanded keeps that position
/// when collapsing, and vice‑versa.
struct SessionGaugeView: View {

    @ObservedObject var viewModel: YouTubeWebViewModel
    @AppStorage("dailyLimitMinutes") private var dailyLimitMinutes: Int = 60

    @State private var isExpanded = true

    // Shared drag state — applies to both expanded and collapsed views
    @State     private var gaugeOffset: CGSize  = .zero
    @GestureState private var gaugeDrag: CGSize = .zero
    // Guards tap-to-toggle from firing at the end of a drag
    @State private var gaugeDragActive: Bool    = false

    var body: some View {
        Group {
            if isExpanded {
                expandedGauge
            } else {
                collapsedPill
            }
        }
        // Single shared offset + drag for both states
        .offset(x: gaugeOffset.width  + gaugeDrag.width,
                y: gaugeOffset.height + gaugeDrag.height)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in gaugeDragActive = true }
                .updating($gaugeDrag) { v, s, _ in s = v.translation }
                .onEnded { v in
                    gaugeOffset.width  += v.translation.width
                    gaugeOffset.height += v.translation.height
                    DispatchQueue.main.async { gaugeDragActive = false }
                }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
    }

    // MARK: - Expanded

    private var expandedGauge: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

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
            guard !gaugeDragActive else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isExpanded = false }
        }
    }

    // MARK: - Collapsed

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
        .transition(.scale(scale: 0.5).combined(with: .opacity))
        .onTapGesture {
            guard !gaugeDragActive else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isExpanded = true }
        }
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
