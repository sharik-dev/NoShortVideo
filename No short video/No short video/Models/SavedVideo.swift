//
//  SavedVideo.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import UIKit

struct SavedVideo: Codable, Identifiable {

    let id: String
    var title: String
    var thumbnailURL: String
    var url: String
    var lastTime: Double
    var duration: Double
    var dateAdded: Date
    /// User-defined folder name. Empty string = no folder.
    var folder: String
    /// Fichier MP4 téléchargé, relatif à `SavedVideo.downloadsDirectory`.
    /// `nil` = vidéo en ligne seulement (favori classique).
    var localFileName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, thumbnailURL, url, lastTime, duration, dateAdded
        case folder
        case localFileName
        case category // legacy
    }

    // Backward-compatible decoder: old JSON used `category`; treat it as `folder`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        title        = try c.decode(String.self, forKey: .title)
        thumbnailURL = try c.decode(String.self, forKey: .thumbnailURL)
        url          = try c.decode(String.self, forKey: .url)
        lastTime     = try c.decode(Double.self, forKey: .lastTime)
        duration     = try c.decode(Double.self, forKey: .duration)
        dateAdded    = try c.decode(Date.self,   forKey: .dateAdded)

        if let f = try c.decodeIfPresent(String.self, forKey: .folder) {
            folder = f
        } else {
            folder = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        }
        localFileName = try c.decodeIfPresent(String.self, forKey: .localFileName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(thumbnailURL, forKey: .thumbnailURL)
        try c.encode(url, forKey: .url)
        try c.encode(lastTime, forKey: .lastTime)
        try c.encode(duration, forKey: .duration)
        try c.encode(dateAdded, forKey: .dateAdded)
        try c.encode(folder, forKey: .folder)
        try c.encodeIfPresent(localFileName, forKey: .localFileName)
    }

    init(
        id: String,
        title: String,
        thumbnailURL: String,
        url: String,
        lastTime: Double,
        duration: Double,
        dateAdded: Date,
        folder: String = "",
        localFileName: String? = nil
    ) {
        self.id           = id
        self.title        = title
        self.thumbnailURL = thumbnailURL
        self.url          = url
        self.lastTime     = lastTime
        self.duration     = duration
        self.dateAdded    = dateAdded
        self.folder       = folder
        self.localFileName = localFileName
    }

    // MARK: - Offline

    /// `Documents/Downloads` : les MP4 téléchargés. Dans Documents plutôt que
    /// Caches, sinon iOS les purge quand le stockage manque — et une vidéo
    /// « disponible hors ligne » qui disparaît sans prévenir ne l'est pas.
    nonisolated static let downloadsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Le fichier local, s'il existe encore sur le disque.
    var localFileURL: URL? {
        guard let name = localFileName else { return nil }
        let url = Self.downloadsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var isOffline: Bool { localFileURL != nil }

    /// Miniature enregistrée à côté du MP4 (cf. `VideoDownloadService`).
    /// Gardée en mémoire : la liste la redemande à chaque rendu, et relire le
    /// disque à chaque fois rendait le défilement saccadé.
    var localThumbnail: UIImage? {
        guard localFileName != nil else { return nil }
        if let cached = Self.thumbnailCache.object(forKey: id as NSString) { return cached }
        let url = Self.downloadsDirectory.appendingPathComponent("\(id).jpg")
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        Self.thumbnailCache.setObject(image, forKey: id as NSString)
        return image
    }

    private static let thumbnailCache = NSCache<NSString, UIImage>()

    // MARK: - Convenience

    static func thumbnailURL(for videoId: String) -> String {
        "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
    }

    var formattedLastTime: String { Self.formatTime(lastTime) }
    var formattedDuration: String { Self.formatTime(duration) }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(lastTime / duration, 1.0)
    }

    static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
