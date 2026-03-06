//
//  YouTubeWebView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI
import WebKit

// MARK: - WKWebView subclass that hides the keyboard accessory bar

/// Removes the input accessory view (black toolbar) that appears above the
/// keyboard when the user taps a text field (e.g. YouTube search bar).
final class NoInputAccessoryWebView: WKWebView {

    /// Swizzle trick: find the content view and nil-out its inputAccessoryView.
    override var inputAccessoryView: UIView? { nil }
}

// MARK: - UIViewRepresentable

/// UIViewRepresentable wrapper that displays the pre‑configured WKWebView.
struct YouTubeWebView: UIViewRepresentable {

    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No dynamic updates needed — the view model drives the web view.
    }
}
