//
//  LibraryView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

/// Library screen showing saved videos with thumbnails, timestamps, and progress.
struct LibraryView: View {

    @StateObject private var libraryVM = LibraryViewModel()
    @ObservedObject var youtubeVM: YouTubeWebViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ZStack {
                // Dark gradient background
                LinearGradient(
                    colors: [Color(.systemBackground), Color.black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if libraryVM.videos.isEmpty {
                    emptyState
                } else {
                    videoList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            libraryVM.load()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Saved Videos")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the bookmark icon while watching\na video to save it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Video List

    private var videoList: some View {
        List {
            ForEach(libraryVM.videos) { video in
                videoRow(video)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        youtubeVM.openVideo(video)
                        isPresented = false
                    }
                    .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                libraryVM.delete(at: offsets)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Video Row

    private func videoRow(_ video: SavedVideo) -> some View {
        HStack(spacing: 14) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                case .failure:
                    thumbnailPlaceholder
                default:
                    thumbnailPlaceholder
                }
            }
            .frame(width: 130, height: 73)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                // Timestamp
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("\(video.formattedLastTime) / \(video.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray5))
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: geo.size.width * video.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }

            Spacer(minLength: 0)

            // Play icon
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
        .padding(.vertical, 6)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "play.rectangle")
                    .foregroundStyle(.secondary)
            )
    }
}
