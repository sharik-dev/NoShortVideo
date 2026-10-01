//
//  OfflineMusicPlayer.swift
//  No short video
//

import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Lecteur des MP3 téléchargés, façon Spotify : une file (la bibliothèque
/// musicale, dans l'ordre affiché), suivant / précédent, aléatoire, répétition
/// de la file ou du morceau, et un volume propre au lecteur.
///
/// Un seul lecteur pour toute l'app : fermer l'écran plein ne coupe pas la
/// musique, la mini-barre la reprend, et l'écran verrouillé la pilote.
final class OfflineMusicPlayer: NSObject, ObservableObject {

    static let shared = OfflineMusicPlayer()

    enum RepeatMode: Int {
        case off, all, one

        var next: RepeatMode { RepeatMode(rawValue: (rawValue + 1) % 3) ?? .off }
    }

    @Published private(set) var queue: [SavedVideo] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var repeatMode: RepeatMode {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: Self.repeatKey) }
    }
    @Published private(set) var shuffle: Bool
    @Published var volume: Float {
        didSet {
            player?.volume = volume
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }

    var current: SavedVideo? { queue.indices.contains(index) ? queue[index] : nil }

    /// Ordre de la bibliothèque, gardé pour revenir en arrière quand on coupe
    /// l'aléatoire.
    private var originalQueue: [SavedVideo] = []
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private let storage = VideoStorageService.music
    private var interruptionMonitor: AudioInterruptionMonitor?
    private var sessionObservers: [NSObjectProtocol] = []

    private static let repeatKey  = "offlineMusicRepeat"
    private static let shuffleKey = "offlineMusicShuffle"
    private static let volumeKey  = "offlineMusicVolume"

    private override init() {
        let defaults = UserDefaults.standard
        repeatMode = RepeatMode(rawValue: defaults.integer(forKey: Self.repeatKey)) ?? .off
        shuffle = defaults.bool(forKey: Self.shuffleKey)
        volume = defaults.object(forKey: Self.volumeKey) as? Float ?? 1
        super.init()
        setupRemoteCommands()
        // Une pub dans une autre app coupe le son : iOS a déjà arrêté le
        // lecteur, on aligne l'état (bouton, écran verrouillé) puis on relance
        // à la fin de la coupure.
        interruptionMonitor = AudioInterruptionMonitor(
            isPlaying: { [weak self] in self?.isPlaying ?? false },
            onBegan: { [weak self] in self?.pausePlayer() },
            resume: { [weak self] in
                guard let self, let player = self.player, !player.isPlaying else { return }
                self.resume()
            }
        )
        observeSession()
    }

    // MARK: - File

    /// Lance `track` dans la file `tracks` (seuls les morceaux présents sur le
    /// disque sont gardés).
    func play(_ track: SavedVideo, in tracks: [SavedVideo]) {
        let playable = tracks.filter { $0.isOffline }
        originalQueue = playable.isEmpty ? [track] : playable
        if shuffle {
            queue = [track] + originalQueue.filter { $0.id != track.id }.shuffled()
            index = 0
        } else {
            queue = originalQueue
            index = queue.firstIndex { $0.id == track.id } ?? 0
        }
        load(resume: true)
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying { pause() } else { resume() }
    }

    /// Pause voulue : la fin d'une coupure audio ne la relancera pas.
    func pause() {
        interruptionMonitor?.cancelPendingResume()
        pausePlayer()
    }

    private func pausePlayer() {
        player?.pause()
        isPlaying = false
        persist()
        updateNowPlaying()
    }

    func resume() {
        guard let player else { return }
        Self.claimSession()
        player.play()
        isPlaying = true
        startTicker()
        updateNowPlaying()
    }

    /// Saute à un morceau déjà dans la file (liste « À suivre »), sans la
    /// rebattre.
    func jump(to track: SavedVideo) {
        guard let target = queue.firstIndex(where: { $0.id == track.id }) else { return }
        persist()
        index = target
        load(resume: false)
    }

    /// Suivant : bouclé en fin de file seulement si la répétition est active.
    func next(userInitiated: Bool = true) {
        guard !queue.isEmpty else { return }
        persist()
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all || userInitiated {
            index = 0
        } else {
            // Fin de file sans répétition : on s'arrête sur le premier morceau.
            index = 0
            load(resume: false, autoplay: false)
            return
        }
        load(resume: false)
    }

    /// Comme Spotify : après trois secondes, « précédent » revient au début du
    /// morceau ; avant, il remonte d'un cran.
    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        persist()
        index = index > 0 ? index - 1 : queue.count - 1
        load(resume: false)
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        updateNowPlaying()
    }

    func toggleShuffle() {
        shuffle.toggle()
        UserDefaults.standard.set(shuffle, forKey: Self.shuffleKey)
        guard let current else { return }
        if shuffle {
            queue = [current] + originalQueue.filter { $0.id != current.id }.shuffled()
            index = 0
        } else {
            queue = originalQueue
            index = queue.firstIndex { $0.id == current.id } ?? 0
        }
    }

    func cycleRepeat() { repeatMode = repeatMode.next }

    /// Ferme la session : plus de mini-barre, plus de contrôles verrouillés.
    func stop() {
        persist()
        player?.stop()
        player = nil
        ticker?.invalidate()
        queue = []
        originalQueue = []
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Le reste de la file, dans l'ordre où il sera joué.
    var upNext: [SavedVideo] {
        guard index + 1 < queue.count else { return [] }
        return Array(queue[(index + 1)...])
    }

    // MARK: - Session audio

    /// Les webviews (YouTube, YouTube Music, Instagram…) réécrivent la
    /// catégorie de la session audio de l'app : une page qui ne contient que
    /// des vidéos muettes la passe en `ambient`. Au premier plan ça ne
    /// s'entend pas, mais iOS coupe une session `ambient` dès que l'app part
    /// en arrière-plan — le MP3 s'arrête, et le suivant ne démarre plus.
    /// On remet `playback` avant chaque lecture.
    private static func claimSession() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || session.categoryOptions.contains(.mixWithOthers) {
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        }
        try? session.setActive(true)
    }

    private func observeSession() {
        let center = NotificationCenter.default
        // Une webview a changé la catégorie pendant que le MP3 joue : on la
        // reprend tout de suite, avant que le passage en arrière-plan ne coupe.
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self, self.isPlaying,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .categoryChange,
                  AVAudioSession.sharedInstance().category != .playback
            else { return }
            Self.claimSession()
        })
        // Filet de sécurité au moment critique : l'app passe en arrière-plan.
        sessionObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isPlaying, let player = self.player else { return }
            Self.claimSession()
            if !player.isPlaying { player.play() }
        })
    }

    // MARK: - Lecture

    private func load(resume: Bool, autoplay: Bool = true) {
        guard let track = current, let url = track.localFileURL else { return }
        player?.stop()
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.delegate = self
        newPlayer.volume = volume
        newPlayer.prepareToPlay()
        player = newPlayer
        duration = newPlayer.duration
        // Reprise là où on l'avait laissé, sauf s'il avait été écouté jusqu'au bout.
        if resume, track.lastTime > 1, track.lastTime < newPlayer.duration - 5 {
            newPlayer.currentTime = track.lastTime
        }
        currentTime = newPlayer.currentTime
        if autoplay { self.resume() } else { isPlaying = false; updateNowPlaying() }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying && !self.isPlaying { self.ticker?.invalidate() }
        }
    }

    private func persist() {
        guard var track = current, currentTime > 0 else { return }
        track.lastTime = currentTime
        if duration > 0 { track.duration = duration }
        storage.save(track)
        if queue.indices.contains(index) { queue[index] = track }
    }

    // MARK: - Écran verrouillé

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        // Les commandes lecture / pause existent déjà (No_short_videoApp) :
        // celles-ci n'agissent que si une session hors ligne est ouverte.
        cc.playCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.resume(); return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.pause(); return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.togglePlay(); return .success
        }
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.next(); return .success
        }
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.previous(); return .success
        }
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, self.player != nil,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .noActionableNowPlayingItem }
            self.seek(to: event.positionTime); return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let art = track.artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - Fin de morceau

extension OfflineMusicPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [self] in
            // Morceau fini : la prochaine écoute repart du début.
            if var track = current {
                track.lastTime = 0
                storage.save(track)
                queue[index] = track
            }
            currentTime = 0
            if repeatMode == .one {
                player.currentTime = 0
                resume()
            } else {
                next(userInitiated: false)
            }
        }
    }
}
