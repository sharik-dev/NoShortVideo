//
//  DailyStatsStore.swift
//  No short video
//
//  Created by Sharik Mohamed on 01/07/2026.
//

import Combine
import Foundation
import UIKit

/// Tracks live usage statistics that reset every day:
/// - number of distinct videos watched today
/// - time spent actively using the app today (in seconds)
///
/// Values are persisted in `UserDefaults` and rolled over automatically
/// when the calendar day changes.
final class DailyStatsStore: ObservableObject {

    static let shared = DailyStatsStore()

    // MARK: - Published State

    @Published private(set) var videosWatchedToday: Int = 0
    @Published private(set) var secondsOnAppToday: TimeInterval = 0

    // MARK: - Storage

    private let defaults = UserDefaults.standard
    private var lastCountedVideoId = ""

    private enum Keys {
        static let day     = "statsDayKey"
        static let videos  = "statsVideosToday"
        static let seconds = "statsSecondsToday"
    }

    // MARK: - Init

    private init() {
        rolloverIfNeeded()
        videosWatchedToday = defaults.integer(forKey: Keys.videos)
        secondsOnAppToday  = defaults.double(forKey: Keys.seconds)

        // Persist the accumulated time before the app is suspended, so a single
        // background/resign event flushes the in-memory counter to disk.
        NotificationCenter.default.addObserver(
            self, selector: #selector(persist),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    // MARK: - Day rollover

    /// Today's key in a stable, locale-independent `yyyy-MM-dd` format.
    private var todayKey: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Resets the counters when a new day begins.
    private func rolloverIfNeeded() {
        guard defaults.string(forKey: Keys.day) != todayKey else { return }
        defaults.set(todayKey, forKey: Keys.day)
        defaults.set(0,   forKey: Keys.videos)
        defaults.set(0.0, forKey: Keys.seconds)
        videosWatchedToday = 0
        secondsOnAppToday  = 0
        lastCountedVideoId = ""
    }

    // MARK: - Recording

    /// Counts a newly opened video. Ignores empty ids and consecutive
    /// duplicates (SPA navigations re-emit the same id several times).
    func recordVideoWatched(id: String) {
        guard !id.isEmpty, id != lastCountedVideoId else { return }
        lastCountedVideoId = id
        rolloverIfNeeded()
        videosWatchedToday += 1
        defaults.set(videosWatchedToday, forKey: Keys.videos)
    }

    /// Adds one second of active app usage. Kept in memory and flushed to disk
    /// on resign/background to avoid spamming `UserDefaults` every second.
    func tick() {
        rolloverIfNeeded()
        secondsOnAppToday += 1
    }

    /// Flushes the in-memory time counter to disk.
    @objc func persist() {
        rolloverIfNeeded()
        defaults.set(secondsOnAppToday, forKey: Keys.seconds)
        defaults.set(videosWatchedToday, forKey: Keys.videos)
    }

    // MARK: - Formatting

    /// `secondsOnAppToday` rendered as `1h 05m`, `12m`, or `45s`.
    var formattedTimeOnApp: String {
        let total = Int(secondsOnAppToday)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
