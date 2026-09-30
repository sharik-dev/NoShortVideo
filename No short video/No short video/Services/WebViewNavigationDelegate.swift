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

        // Certains sites — X en tête — tentent de nous éjecter vers Safari via
        // un schéma maison (`x-safari-https://…`). WKWebView ne sait pas le
        // suivre : la navigation échoue et l'ancienne page reste à l'écran. On
        // le réécrit en https et on continue dans l'app, ce qui est tout
        // l'intérêt d'un navigateur dédié.
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme.hasPrefix("x-safari-") {
            decisionHandler(.cancel)
            let stripped = url.absoluteString.replacingOccurrences(
                of: "\(scheme)://", with: scheme.hasSuffix("https") ? "https://" : "http://"
            )
            if let rewritten = URL(string: stripped) {
                webView.load(URLRequest(url: rewritten))
            }
            return
        }

        // Identité Safari : seulement là où elle sert (cf. `safariUserAgent`).
        //
        // Jamais sur un retour/avance ni sur un envoi de formulaire : rejouer
        // la requête y perdrait la position dans l'historique ou le corps du
        // POST. Ces navigations gardent l'UA en place, ce qui est sans
        // conséquence — la page a déjà été servie une fois.
        if navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType != .backForward,
           navigationAction.navigationType != .formSubmitted,
           navigationAction.navigationType != .formResubmitted,
           navigationAction.request.httpMethod == "GET",
           let url = navigationAction.request.url,
           url.scheme?.hasPrefix("http") == true {

            let wanted = Self.userAgent(for: url)
            // WKWebView rend "" (et non nil) une fois l'UA remis à nil : sans
            // cette normalisation, "" != nil vaut toujours vrai et YouTube
            // s'annulait puis se rechargeait en boucle — écran noir, téléphone
            // à 100 % de CPU.
            let current = webView.customUserAgent.flatMap { $0.isEmpty ? nil : $0 }
            if current != wanted {
                webView.customUserAgent = wanted
                // L'en-tête part avec la requête : il faut la rejouer pour que
                // le nouvel UA serve. La passe suivante trouvera l'UA déjà bon
                // et laissera filer — pas de boucle.
                decisionHandler(.cancel)
                webView.load(URLRequest(url: url))
                return
            }
        }

        // Allow all navigations inside the web view — never open Safari.
        decisionHandler(.allow)
    }

    // MARK: - User-Agent

    /// UA complet de Safari sur iOS.
    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// L'UA à présenter selon le site — `nil` = celui de WKWebView, qui
    /// s'annonce comme un navigateur embarqué.
    ///
    /// Se faire passer pour Safari partout coûtait cher : YouTube et YouTube
    /// Music, voyant un navigateur complet, servent leur régie publicitaire
    /// habituelle — d'où les annonces avec bouton « Passer » apparues alors que
    /// la version publiée sur l'App Store n'en avait aucune. En navigateur
    /// embarqué, ce pipeline ne se déclenche pas.
    ///
    /// X, lui, a besoin de l'inverse : sans le jeton « Safari » il nous prend
    /// pour une WebView et tente de nous éjecter via `x-safari-https://`.
    /// L'identité Safari est donc réservée aux domaines qui l'exigent.
    static func userAgent(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if on("x.com") || on("twitter.com") { return safariUserAgent }
        return nil
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

    /// iOS tue le processus de rendu quand une page devient trop lourde — c'est
    /// ce qui arrivait sur un fil Instagram longuement déroulé. Sans ce
    /// rattrapage, la webview reste blanche définitivement : l'app « coupe ».
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let url = webView.url {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
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

