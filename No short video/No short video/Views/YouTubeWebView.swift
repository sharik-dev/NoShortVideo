//
//  YouTubeWebView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI
import WebKit

/// UIViewRepresentable wrapper that displays the pre‑configured WKWebView.
struct YouTubeWebView: UIViewRepresentable {

    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No dynamic updates needed — the view model drives the web view.
    }
}
