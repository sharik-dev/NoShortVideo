//
//  VideoStorageService.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Foundation

/// Persists saved videos as a JSON file in the app's Documents directory.
final class VideoStorageService {

    /// Vidéos YouTube enregistrées depuis la webview principale.
    static let shared = VideoStorageService(fileName: "saved_videos.json")

    /// Morceaux YouTube Music, dans leur propre fichier : mélanger les deux
    /// ferait apparaître des musiques dans la bibliothèque vidéo et l'inverse.
    static let music  = VideoStorageService(fileName: "saved_music.json")

    private let fileName: String
    private let queue = DispatchQueue(label: "com.noshort.videostorage", qos: .utility)

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private init(fileName: String) {
        self.fileName = fileName
    }

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
                if video.localFileName != nil {
                    videos[index].localFileName = video.localFileName
                }
            } else {
                videos.append(video)
            }
            writeUnsafe(videos)
        }
    }

    /// Updates the folder of a saved video.
    func updateFolder(videoId: String, folder: String) {
        queue.sync {
            var videos = loadAllUnsafe()
            guard let index = videos.firstIndex(where: { $0.id == videoId }) else { return }
            videos[index].folder = folder
            writeUnsafe(videos)
        }
    }

    /// Deletes a video by its ID — and its MP4, if it was downloaded.
    func delete(videoId: String) {
        queue.sync {
            var videos = loadAllUnsafe()
            for video in videos where video.id == videoId {
                if let name = video.localFileName {
                    let dir = SavedVideo.downloadsDirectory
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(video.id).jpg"))
                }
            }
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
