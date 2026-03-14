//
//  No_short_videoApp.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import AVFoundation
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
