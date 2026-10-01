//
//  AudioInterruptionMonitor.swift
//  No short video
//

import AVFoundation
import UIKit

/// Relance un lecteur quand une autre app a fini de lui couper le son.
///
/// Le cas visé : on ouvre une app dont la pub démarre avec du son, iOS coupe
/// notre musique, la pub se termine… et la musique ne repart pas. iOS envoie
/// bien une fin d'interruption, mais avec « ne pas reprendre » la plupart du
/// temps — et parfois il n'envoie rien du tout, quand l'app gênante oublie de
/// prévenir en libérant l'audio.
///
/// Règle : **ce qui jouait avant la coupure rejoue après**, quoi que suggère
/// iOS. Ce qui était en pause reste en pause.
///
/// Un moniteur par lecteur : chacun dit s'il jouait et sait se relancer.
final class AudioInterruptionMonitor {

    private let isPlaying: () -> Bool
    private let onBegan: () -> Void
    private let resume: () -> Void

    /// Le lecteur jouait quand la coupure a commencé, et n'a pas encore été
    /// relancé.
    private var pendingResume = false
    private var observers: [NSObjectProtocol] = []

    /// Le son revient parfois avant que l'autre app ait vraiment lâché l'audio :
    /// la première relance échoue en silence. On insiste un peu. Les relances
    /// doivent donc être sans effet sur un lecteur qui joue déjà.
    private static let retryDelays: [TimeInterval] = [0, 1, 2.5]

    /// Vrai quand on est sur un réseau social (Instagram, X…) : là, la musique
    /// passe avant tout. Si une vidéo de la page lui prend quand même l'audio
    /// (son réactivé d'une façon que `MusicPriorityService` n'a pas vue), on
    /// n'attend pas qu'elle se termine — dans un fil, elle ne se terminerait
    /// jamais : on relance tout de suite, et c'est la vidéo qui cède.
    ///
    /// Un appel téléphonique garde la main : iOS refuse alors de réactiver la
    /// session, les relances échouent sans bruit et la fin de coupure reprend
    /// le relais normalement.
    static var musicHasPriority = false

    private static let priorityRetryDelays: [TimeInterval] = [0.4, 1.2, 2.5]

    init(isPlaying: @escaping () -> Bool,
         onBegan: @escaping () -> Void = {},
         resume: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.onBegan = onBegan
        self.resume = resume

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] in self?.handle($0) })

        // Filet de sécurité : l'app gênante n'a jamais signalé la fin. On
        // relance au moins en revenant dans l'app.
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.resumeIfPending() })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Le lecteur a été mis en pause exprès (par l'utilisateur, ou parce
    /// qu'un autre son de l'app a pris le relais) : il ne doit plus repartir
    /// tout seul à la fin de la coupure — il couperait ce qui joue à sa place.
    func cancelPendingResume() { pendingResume = false }

    private func handle(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // Coupure « rétroactive » signalée au réveil d'une app suspendue :
            // rien n'a réellement été interrompu à ce moment-là.
            if let r = info[AVAudioSessionInterruptionReasonKey] as? UInt,
               AVAudioSession.InterruptionReason(rawValue: r) == .appWasSuspended { return }
            guard isPlaying() else { return }
            pendingResume = true
            onBegan()
            if Self.musicHasPriority { reclaim() }
        case .ended:
            // `shouldResume` volontairement ignoré : c'est lui qui laissait la
            // musique muette après une pub.
            resumeIfPending()
        @unknown default:
            break
        }
    }

    /// Relance sans attendre la fin de la coupure. `pendingResume` reste
    /// levé : si iOS refuse (appel en cours), la fin de coupure relancera.
    private func reclaim() {
        // Les relances sont sans effet sur un lecteur qui joue déjà : on les
        // enchaîne toutes, la première peut échouer en silence.
        for (i, delay) in Self.priorityRetryDelays.enumerated() {
            let isLast = i == Self.priorityRetryDelays.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.pendingResume, Self.musicHasPriority else { return }
                guard (try? AVAudioSession.sharedInstance().setActive(true)) != nil else { return }
                self.resume()
                if isLast { self.pendingResume = false }
            }
        }
    }

    private func resumeIfPending() {
        guard pendingResume else { return }
        pendingResume = false
        for delay in Self.retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.resume()
            }
        }
    }
}
