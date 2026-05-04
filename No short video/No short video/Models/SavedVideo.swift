//
//  SavedVideo.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Foundation

struct SavedVideo: Codable, Identifiable {

    let id: String
    var title: String
    var thumbnailURL: String
    var url: String
    var lastTime: Double
    var duration: Double
    var dateAdded: Date
    var category: String

    enum CodingKeys: String, CodingKey {
        case id, title, thumbnailURL, url, lastTime, duration, dateAdded, category
    }

    // Custom decoder so existing JSON without "category" still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        title        = try c.decode(String.self, forKey: .title)
        thumbnailURL = try c.decode(String.self, forKey: .thumbnailURL)
        url          = try c.decode(String.self, forKey: .url)
        lastTime     = try c.decode(Double.self, forKey: .lastTime)
        duration     = try c.decode(Double.self, forKey: .duration)
        dateAdded    = try c.decode(Date.self,   forKey: .dateAdded)
        category     = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
    }

    init(
        id: String,
        title: String,
        thumbnailURL: String,
        url: String,
        lastTime: Double,
        duration: Double,
        dateAdded: Date,
        category: String = ""
    ) {
        self.id           = id
        self.title        = title
        self.thumbnailURL = thumbnailURL
        self.url          = url
        self.lastTime     = lastTime
        self.duration     = duration
        self.dateAdded    = dateAdded
        self.category     = category
    }

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
