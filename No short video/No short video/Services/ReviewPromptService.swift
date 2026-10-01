//
//  ReviewPromptService.swift
//  No short video
//

import Combine
import Foundation

/// Décide **quand** proposer la note App Store (la feuille native à étoiles,
/// `requestReview`) — jamais **si** elle s'affiche : iOS garde le dernier mot
/// et ne la montre pas plus de trois fois par an.
///
/// Les règles suivent les recommandations d'Apple (HIG, « Ratings and reviews ») :
/// - jamais au premier lancement : il faut avoir vraiment utilisé l'app
///   (plusieurs jours distincts d'usage) ;
/// - juste après un **moment de réussite** — un téléchargement terminé, une
///   vidéo ou un morceau enregistré — jamais au milieu d'une tâche ;
/// - pas deux fois pour la même version, et de longs mois entre deux demandes ;
/// - aucune fenêtre maison avant la feuille système, aucun bouton qui la
///   déclenche : c'est l'app qui choisit le moment.
@MainActor
final class ReviewPromptService: ObservableObject {

    static let shared = ReviewPromptService()

    /// Passe à `true` quand le moment est venu ; `ContentView` présente la
    /// feuille (si rien ne s'y oppose à l'écran) puis appelle `didAsk()`.
    @Published private(set) var isDue = false

    // Seuils
    private let minActiveDays = 3
    private let minDaysSinceInstall = 4
    private let minSuccesses = 3
    private let minDaysBetweenAsks = 120

    private let defaults = UserDefaults.standard
    private enum Key {
        static let installDate   = "review.installDate"
        static let activeDays    = "review.activeDays"
        static let lastActiveDay = "review.lastActiveDay"
        static let successes     = "review.successes"
        static let lastAskDate   = "review.lastAskDate"
        static let lastAskVersion = "review.lastAskVersion"
    }

    private init() {
        if defaults.object(forKey: Key.installDate) == nil {
            defaults.set(Date(), forKey: Key.installDate)
        }
    }

    /// À chaque retour au premier plan : compte les jours distincts d'usage.
    func recordActiveDay() {
        let today = Self.dayStamp(Date())
        guard defaults.string(forKey: Key.lastActiveDay) != today else { return }
        defaults.set(today, forKey: Key.lastActiveDay)
        defaults.set(defaults.integer(forKey: Key.activeDays) + 1, forKey: Key.activeDays)
    }

    /// Un moment où l'utilisateur vient d'obtenir ce qu'il voulait.
    func recordSuccess() {
        defaults.set(defaults.integer(forKey: Key.successes) + 1, forKey: Key.successes)
        guard isEligible else { return }
        // Laisser le toast « Sauvegardé » / la pastille de fin s'afficher
        // avant de poser la feuille par-dessus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.isDue = true
        }
    }

    /// La feuille vient d'être demandée à iOS : on repart de zéro.
    func didAsk() {
        isDue = false
        defaults.set(Date(), forKey: Key.lastAskDate)
        defaults.set(Self.appVersion, forKey: Key.lastAskVersion)
        defaults.set(0, forKey: Key.successes)
    }

    /// Le moment n'était pas bon (onboarding, écran de blocage…) : on attendra
    /// la prochaine réussite.
    func postpone() {
        isDue = false
    }

    #if DEBUG
    /// `-debugReview YES` : force la feuille pour la vérifier au simulateur.
    func debugForce() { isDue = true }
    #endif

    private var isEligible: Bool {
        let now = Date()
        let install = defaults.object(forKey: Key.installDate) as? Date ?? now
        guard Self.days(from: install, to: now) >= minDaysSinceInstall,
              defaults.integer(forKey: Key.activeDays) >= minActiveDays,
              defaults.integer(forKey: Key.successes) >= minSuccesses,
              defaults.string(forKey: Key.lastAskVersion) != Self.appVersion
        else { return false }
        if let last = defaults.object(forKey: Key.lastAskDate) as? Date,
           Self.days(from: last, to: now) < minDaysBetweenAsks {
            return false
        }
        return true
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
