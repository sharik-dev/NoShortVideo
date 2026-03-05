//
//  WebViewNavigationDelegate.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import WebKit

/// Navigation delegate that keeps browsing inside the web view
/// and syncs state back to `WebViewState`.
final class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {

    private let state: WebViewState

    /// Called when a page finishes loading (used for resume-seek).
    var onDidFinish: (() -> Void)?

    init(state: WebViewState) {
        self.state = state
    }

    // MARK: - Navigation Policy

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Allow all navigations inside the web view — never open Safari.
        decisionHandler(.allow)
    }

    // MARK: - State Syncing

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateState(from: webView, isLoading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateState(from: webView, isLoading: true)
        // Re‑inject scripts on SPA navigations.
        webView.evaluateJavaScript(ScriptInjectionService.allScripts, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState(from: webView, isLoading: false)
        // Final pass to catch any late‑loaded Shorts.
        webView.evaluateJavaScript(ScriptInjectionService.allScripts, completionHandler: nil)
        // Notify ViewModel for pending seek.
        onDidFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateState(from: webView, isLoading: false)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateState(from: webView, isLoading: false)
    }

    // MARK: - Helpers

    private func updateState(from webView: WKWebView, isLoading: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.state.canGoBack = webView.canGoBack
            self?.state.canGoForward = webView.canGoForward
            self?.state.isLoading = isLoading
            self?.state.currentURL = webView.url
            self?.state.pageTitle = webView.title ?? ""

            // Detect if we are on a video watch page
            if let url = webView.url,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value,
               !videoId.isEmpty {
                self?.state.isOnVideoPage = true
                self?.state.currentVideoId = videoId
            } else {
                self?.state.isOnVideoPage = false
                self?.state.currentVideoId = ""
            }
        }
    }
}
