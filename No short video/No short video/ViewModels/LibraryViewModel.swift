//
//  LibraryViewModel.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Combine
import SwiftUI

/// ViewModel for the Library screen.
final class LibraryViewModel: ObservableObject {

    @Published var videos: [SavedVideo] = []

    private let storage = VideoStorageService.shared

    // MARK: - Actions

    func load() {
        videos = storage.loadAll()
    }

    func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { videos[$0].id }
        idsToDelete.forEach { storage.delete(videoId: $0) }
        videos.remove(atOffsets: offsets)
    }

    func delete(video: SavedVideo) {
        storage.delete(videoId: video.id)
        videos.removeAll { $0.id == video.id }
    }
}
