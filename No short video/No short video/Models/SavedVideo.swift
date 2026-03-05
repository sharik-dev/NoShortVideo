//
//  SavedVideo.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Foundation

/// A video bookmarked by the user, with its playback timestamp.
struct SavedVideo: Codable, Identifiable {

    /// YouTube video ID (e.g. "dQw4w9WgXcQ").
    let id: String

    /// Video title extracted from the page.
    var title: String

    /// Thumbnail URL built from the video ID.
    var thumbnailURL: String

    /// Full YouTube watch URL.
    var url: String

    /// Playback position in seconds where the user stopped.
    var lastTime: Double

    /// Total video duration in seconds.
    var duration: Double

    /// Date the video was first saved.
    var dateAdded: Date

    // MARK: - Convenience

    /// Builds the standard HQ thumbnail URL for a YouTube video.
    static func thumbnailURL(for videoId: String) -> String {
        "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
    }

    /// Formatted timestamp string, e.g. "5:12".
    var formattedLastTime: String {
        Self.formatTime(lastTime)
    }

    /// Formatted duration string, e.g. "10:30".
    var formattedDuration: String {
        Self.formatTime(duration)
    }

    /// Watch progress as a fraction 0…1.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(lastTime / duration, 1.0)
    }

    static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
