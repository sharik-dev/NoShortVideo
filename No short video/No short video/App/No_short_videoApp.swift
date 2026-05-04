//
//  No_short_videoApp.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import AVFoundation
import MediaPlayer
import SwiftUI

@main
struct No_short_videoApp: App {
    init() {
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
