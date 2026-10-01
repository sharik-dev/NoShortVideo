//
//  DownloadProgressPill.swift
//  No short video
//
//  Created by Sharik Mohamed on 30/09/2026.
//

import SwiftUI

/// Pastille en haut de l'écran pendant un téléchargement : anneau de
/// progression, étape en cours, pourcentage. Un appui ouvre les
/// téléchargements.
///
/// Deux étapes, parce que ce sont deux attentes de nature différente : le site
/// convertit d'abord la vidéo (on ne contrôle rien, on affiche son
/// pourcentage), puis le fichier descend sur le téléphone (vraie progression en
/// Mo).
struct DownloadProgressPill: View {

    let job: DownloadJob
    var onTap: () -> Void
    var onClose: () -> Void

    @AppStorage("appLanguage") private var lang: String = "en"
    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        HStack(spacing: 12) {
            indicator
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(stepLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if job.format == .mp3 {
                        Text("MP3")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Text(job.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if !job.isOver {
                Text("\(Int((job.progress * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.25), value: job.progress)
    }

    @ViewBuilder
    private var indicator: some View {
        switch job.phase {
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
        case .waiting:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
        case .preparing, .downloading:
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: max(0.03, job.progress))
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: job.phase == .downloading ? "arrow.down" : "gearshape.fill")
                    .font(.system(size: 11, weight: .bold))
            }
        }
    }

    private var stepLabel: String {
        switch job.phase {
        case .preparing(let provider):
            return t("Préparation · \(provider.displayName)", "Preparing · \(provider.displayName)")
        case .downloading:
            if job.expectedBytes > 0 {
                return t("Téléchargement · \(mb(job.receivedBytes)) / \(mb(job.expectedBytes))",
                         "Downloading · \(mb(job.receivedBytes)) / \(mb(job.expectedBytes))")
            }
            return t("Téléchargement · \(mb(job.receivedBytes))", "Downloading · \(mb(job.receivedBytes))")
        case .finished:
            return t("Disponible hors ligne", "Available offline")
        case .failed:
            return t("Échec du téléchargement", "Download failed")
        case .waiting:
            return t("Interrompu · reprendra tout seul", "Interrupted · will resume")
        }
    }

    private func mb(_ bytes: Int64) -> String {
        String(format: "%.1f Mo", Double(bytes) / 1_048_576)
            .replacingOccurrences(of: "Mo", with: lang == "fr" ? "Mo" : "MB")
    }
}
