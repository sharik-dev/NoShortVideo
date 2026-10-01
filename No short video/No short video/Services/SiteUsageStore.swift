//
//  SiteUsageStore.swift
//  No short video
//

import Combine
import Foundation
import SwiftUI
import UIKit

/// Un site tel que l'écran de statistiques le compte.
///
/// Plus fin que `BrowserPanel` : YouTube Music a sa propre ligne, et une page
/// quelconque ouverte depuis YouTube tombe dans « Web ».
enum UsageSite: String, CaseIterable, Identifiable {
    case youtube, music, twitch, instagram, linkedin, x, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube:   return "YouTube"
        case .music:     return "YT Music"
        case .twitch:    return "Twitch"
        case .instagram: return "Instagram"
        case .linkedin:  return "LinkedIn"
        case .x:         return "X"
        case .other:     return "Web"
        }
    }

    /// Mêmes symboles que les tuiles de l'accueil.
    var icon: String {
        switch self {
        case .youtube:   return "play.rectangle.fill"
        case .music:     return "music.note"
        case .twitch:    return "gamecontroller.fill"
        case .instagram: return "camera.fill"
        case .linkedin:  return "briefcase.fill"
        case .x:         return "paperplane.fill"
        case .other:     return "globe"
        }
    }

    init(_ kind: SiteKind) {
        switch kind {
        case .youtube:   self = .youtube
        case .twitch:    self = .twitch
        case .instagram: self = .instagram
        case .linkedin:  self = .linkedin
        case .x:         self = .x
        case .other:     self = .other
        }
    }
}

/// Temps passé et nombre d'ouvertures, par site et par jour.
///
/// Tout tient dans un seul dictionnaire `jour → site → valeur` rangé dans
/// `UserDefaults`, élagué à `retentionDays` jours : quelques centaines
/// d'octets, pas de quoi sortir une base de données.
final class SiteUsageStore: ObservableObject {

    static let shared = SiteUsageStore()

    /// `yyyy-MM-dd` → site → secondes.
    @Published private(set) var seconds: [String: [String: Double]] = [:]
    /// `yyyy-MM-dd` → site → ouvertures.
    @Published private(set) var opens: [String: [String: Int]] = [:]

    private let defaults = UserDefaults.standard
    private let retentionDays = 30
    private var ticksSinceFlush = 0

    private enum Keys {
        static let seconds = "siteUsageSeconds"
        static let opens   = "siteUsageOpens"
    }

    private init() {
        seconds = defaults.dictionary(forKey: Keys.seconds) as? [String: [String: Double]] ?? [:]
        opens   = defaults.dictionary(forKey: Keys.opens)   as? [String: [String: Int]]    ?? [:]
        NotificationCenter.default.addObserver(
            self, selector: #selector(persist),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    // MARK: - Jours

    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Les `count` derniers jours, du plus ancien à aujourd'hui.
    static func lastDays(_ count: Int) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    // MARK: - Enregistrement

    /// Une seconde de plus sur `site`. Gardée en mémoire, écrite toutes les
    /// 15 s et à la mise en arrière-plan.
    func tick(_ site: UsageSite) {
        let day = Self.dayKey()
        seconds[day, default: [:]][site.rawValue, default: 0] += 1
        ticksSinceFlush += 1
        if ticksSinceFlush >= 15 { persist() }
    }

    func recordOpen(_ site: UsageSite) {
        let day = Self.dayKey()
        opens[day, default: [:]][site.rawValue, default: 0] += 1
        persist()
    }

    @objc func persist() {
        ticksSinceFlush = 0
        prune()
        defaults.set(seconds, forKey: Keys.seconds)
        defaults.set(opens,   forKey: Keys.opens)
    }

    private func prune() {
        let keep = Set(Self.lastDays(retentionDays).map { Self.dayKey($0) })
        seconds = seconds.filter { keep.contains($0.key) }
        opens   = opens.filter   { keep.contains($0.key) }
    }

    // MARK: - Lecture

    func seconds(on day: Date, site: UsageSite) -> Double {
        seconds[Self.dayKey(day)]?[site.rawValue] ?? 0
    }

    func seconds(on day: Date) -> Double {
        seconds[Self.dayKey(day)]?.values.reduce(0, +) ?? 0
    }

    func seconds(site: UsageSite, days: [Date]) -> Double {
        days.reduce(0) { $0 + seconds(on: $1, site: site) }
    }

    func opens(site: UsageSite, days: [Date]) -> Int {
        days.reduce(0) { $0 + (opens[Self.dayKey($1)]?[site.rawValue] ?? 0) }
    }

    /// `1h 05m`, `12m` ou `45s`.
    static func format(_ value: Double) -> String {
        let total = Int(value)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
