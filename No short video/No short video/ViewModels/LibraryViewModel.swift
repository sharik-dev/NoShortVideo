//
//  LibraryViewModel.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Combine
import SwiftUI

final class LibraryViewModel: ObservableObject {

    @Published var videos: [SavedVideo] = []
    @Published var selectedCategory: String? = nil

    private let storage = VideoStorageService.shared

    // MARK: - Derived

    var allCategories: [String] {
        Array(Set(videos.compactMap { $0.category.isEmpty ? nil : $0.category })).sorted()
    }

    var filteredVideos: [SavedVideo] {
        guard let cat = selectedCategory else { return videos }
        return videos.filter { $0.category == cat }
    }

    // MARK: - Actions

    func load() {
        videos = storage.loadAll()
    }

    func delete(video: SavedVideo) {
        storage.delete(videoId: video.id)
        videos.removeAll { $0.id == video.id }
    }

    func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredVideos[$0].id }
        idsToDelete.forEach { storage.delete(videoId: $0) }
        videos.removeAll { idsToDelete.contains($0.id) }
    }

    func setCategory(_ category: String, for video: SavedVideo) {
        storage.updateCategory(videoId: video.id, category: category)
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index].category = category
        }
    }
}
