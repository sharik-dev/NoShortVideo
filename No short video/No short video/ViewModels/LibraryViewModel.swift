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
    @Published var selectedFolder: String? = nil

    private let storage = VideoStorageService.shared

    // MARK: - Derived

    /// Folder names present across all saved videos (sorted, deduped).
    var allFolders: [String] {
        Array(Set(videos.compactMap { $0.folder.isEmpty ? nil : $0.folder })).sorted()
    }

    var filteredVideos: [SavedVideo] {
        guard let f = selectedFolder else { return videos }
        return videos.filter { $0.folder == f }
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

    func setFolder(_ folder: String, for video: SavedVideo) {
        storage.updateFolder(videoId: video.id, folder: folder)
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index].folder = folder
        }
    }
}
