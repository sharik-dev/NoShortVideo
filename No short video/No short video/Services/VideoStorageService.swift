//
//  VideoStorageService.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Foundation

/// Persists saved videos as a JSON file in the app's Documents directory.
final class VideoStorageService {

    static let shared = VideoStorageService()

    private let fileName = "saved_videos.json"
    private let queue = DispatchQueue(label: "com.noshort.videostorage", qos: .utility)

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private init() {}

    // MARK: - Public API

    /// Loads all saved videos, sorted by date added (newest first).
    func loadAll() -> [SavedVideo] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let videos = try? JSONDecoder().decode([SavedVideo].self, from: data)
            else { return [] }
            return videos.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    /// Saves or updates a video (upsert by id).
    func save(_ video: SavedVideo) {
        queue.sync {
            var videos = loadAllUnsafe()
            if let index = videos.firstIndex(where: { $0.id == video.id }) {
                videos[index].lastTime = video.lastTime
                videos[index].duration = video.duration
                videos[index].title = video.title
            } else {
                videos.append(video)
            }
            writeUnsafe(videos)
        }
    }

    /// Deletes a video by its ID.
    func delete(videoId: String) {
        queue.sync {
            var videos = loadAllUnsafe()
            videos.removeAll { $0.id == videoId }
            writeUnsafe(videos)
        }
    }

    // MARK: - Internal (must be called inside queue)

    private func loadAllUnsafe() -> [SavedVideo] {
        guard let data = try? Data(contentsOf: fileURL),
              let videos = try? JSONDecoder().decode([SavedVideo].self, from: data)
        else { return [] }
        return videos
    }

    private func writeUnsafe(_ videos: [SavedVideo]) {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
