//
//  YouTubeWebViewModel.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Combine
import WebKit

/// Central view model that owns and configures the WKWebView.
final class YouTubeWebViewModel: ObservableObject {

    // MARK: - Published State

    @Published var webViewState = WebViewState()

    // MARK: - Properties

    let webView: WKWebView
    private let navigationDelegate: WebViewNavigationDelegate

    // MARK: - Init

    init() {
        let state = WebViewState()

        // Configure the web view
        let configuration = WKWebViewConfiguration()

        // Inject scripts
        let contentController = WKUserContentController()
        contentController.addUserScript(ScriptInjectionService.userScript())
        configuration.userContentController = contentController

        // Media settings
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Cookie / session persistence
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // Create web view
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        // Navigation delegate
        let navDelegate = WebViewNavigationDelegate(state: state)
        webView.navigationDelegate = navDelegate

        self.webView = webView
        self.navigationDelegate = navDelegate
        self.webViewState = state
    }

    // MARK: - Actions

    func loadYouTube() {
        let request = URLRequest(url: AppConstants.youtubeURL)
        webView.load(request)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func goHome() {
        loadYouTube()
    }
}
