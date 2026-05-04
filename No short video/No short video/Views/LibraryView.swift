//
//  LibraryView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

private let predefinedCategories = [
    "Watch Later", "Music", "Tech", "Sport", "Education", "Entertainment"
]

struct LibraryView: View {

    @StateObject private var libraryVM = LibraryViewModel()
    @ObservedObject var youtubeVM: YouTubeWebViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if libraryVM.videos.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        if !libraryVM.allCategories.isEmpty {
                            categoryFilterBar
                        }
                        videoList
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { libraryVM.load() }
    }

    // MARK: - Category Filter

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "All", value: nil)
                ForEach(libraryVM.allCategories, id: \.self) { cat in
                    categoryChip(label: cat, value: cat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func categoryChip(label: String, value: String?) -> some View {
        Button { libraryVM.selectedCategory = value } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(libraryVM.selectedCategory == value ? Color.red : Color(.systemGray5))
                .foregroundStyle(libraryVM.selectedCategory == value ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            ForEach(libraryVM.filteredVideos) { video in
                videoRow(video)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        youtubeVM.openVideo(video)
                        isPresented = false
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            libraryVM.delete(video: video)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        categoryMenu(for: video)
                        Divider()
                        Button(role: .destructive) {
                            libraryVM.delete(video: video)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func categoryMenu(for video: SavedVideo) -> some View {
        Menu {
            ForEach(predefinedCategories, id: \.self) { cat in
                Button {
                    libraryVM.setCategory(cat, for: video)
                } label: {
                    if video.category == cat {
                        Label(cat, systemImage: "checkmark")
                    } else {
                        Text(cat)
                    }
                }
            }
            if !video.category.isEmpty {
                Divider()
                Button(role: .destructive) {
                    libraryVM.setCategory("", for: video)
                } label: {
                    Label("Remove Category", systemImage: "tag.slash")
                }
            }
        } label: {
            Label("Set Category", systemImage: "tag")
        }
    }

    // MARK: - Video Row

    private func videoRow(_ video: SavedVideo) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                default:
                    thumbnailPlaceholder
                }
            }
            .frame(width: 130, height: 73)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if !video.category.isEmpty {
                    Text(video.category)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.18))
                        .foregroundStyle(Color.red)
                        .clipShape(Capsule())
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(video.formattedLastTime) / \(video.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
        .padding(.vertical, 6)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
    }
}
