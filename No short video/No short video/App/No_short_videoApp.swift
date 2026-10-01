//
//  No_short_videoApp.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Le seul besoin d'un délégué d'app : la session de téléchargement
/// d'arrière-plan, que SwiftUI ne sait pas relayer.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Tôt, avant tout écran : iOS livre à la session recréée les
        // transferts finis ou coupés pendant que l'app n'existait pas.
        VideoDownloadService.shared.restore()
        return true
    }

    /// L'app est réveillée (ou relancée) en arrière-plan parce qu'un
    /// téléchargement s'est terminé sans elle.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        VideoDownloadService.shared.backgroundCompletionHandler = completionHandler
    }
}

@main
struct No_short_videoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Premier lancement : l'app parle la langue du téléphone (FR si le
        // français est en tête, EN sinon). Le choix manuel prend ensuite le
        // relais — onboarding ou Réglages.
        if UserDefaults.standard.string(forKey: "appLanguage") == nil {
            let preferred = Locale.preferredLanguages.first ?? "en"
            UserDefaults.standard.set(preferred.hasPrefix("fr") ? "fr" : "en", forKey: "appLanguage")
        }
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .moviePlayback,
            options: []
        )
        try? AVAudioSession.sharedInstance().setActive(true)
        setupRemoteCommandCenter()
    }

    // Registers the app as an active media player so iOS never shows
    // the "Do you want to continue listening?" interruption prompt.
    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { _ in .success }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { _ in .success }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { _ in .success }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
