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
    @Published var showSavedFeedback: Bool = false
    @Published var showSaveError: Bool = false
    @Published var saveErrorMessage: String = ""
    @Published var sessionProgress: Double = 0.0 // 0.0 to 1.0

    // MARK: - Properties

    let webView: WKWebView
    private let navigationDelegate: WebViewNavigationDelegate
    private let storage = VideoStorageService.shared
    private var trackingTimer: Timer?
    private var pendingSeekTime: Double?
    private var urlObservation: NSKeyValueObservation?
    private var sessionTimer: Timer?
    private var sessionStartTime: Date?

    // MARK: - Init

    init() {
        let state = WebViewState()

        // Configure the web view
        let configuration = WKWebViewConfiguration()

        // Inject scripts
        let contentController = WKUserContentController()
        // Must run before YouTube's scripts to override the Visibility API
        contentController.addUserScript(ScriptInjectionService.backgroundAudioUserScript())
        contentController.addUserScript(ScriptInjectionService.userScript())
        configuration.userContentController = contentController

        // Media settings
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Cookie / session persistence
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // On iPhone: force mobile site. On iPad/Mac: let YouTube serve the desktop site.
        let prefs = WKWebpagePreferences()
        let isCompact = UIDevice.current.userInterfaceIdiom == .phone
        prefs.preferredContentMode = isCompact ? .mobile : .recommended
        configuration.defaultWebpagePreferences = prefs

        // Create web view (custom subclass hides keyboard accessory bar)
        let webView = NoInputAccessoryWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        // Navigation delegate
        let navDelegate = WebViewNavigationDelegate(state: state)
        webView.navigationDelegate = navDelegate

        self.webView = webView
        self.navigationDelegate = navDelegate
        self.webViewState = state

        // Hook seek-on-load for video resume
        self.navigationDelegate.onDidFinish = { [weak self] in
            self?.performPendingSeek()
        }

        // KVO: observe URL changes for SPA navigations (YouTube mobile)
        self.urlObservation = webView.observe(\.url, options: [.new]) { [weak state] webView, _ in
            DispatchQueue.main.async {
                state?.currentURL = webView.url
                state?.canGoBack = webView.canGoBack
                state?.canGoForward = webView.canGoForward
                state?.pageTitle = webView.title ?? ""

                if let url = webView.url,
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value,
                   !videoId.isEmpty {
                    state?.isOnVideoPage = true
                    state?.currentVideoId = videoId
                } else {
                    state?.isOnVideoPage = false
                    state?.currentVideoId = ""
                }
            }
        }

        // Start observing video page changes for auto-tracking
        startObservingVideoPage()

        // Start session timer
        startSessionTimer()

        // When the app is backgrounded, YouTube may still pause via its own
        // player logic. Force a play() call to counteract it.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.webView.evaluateJavaScript(
                "var v=document.querySelector('video'); if(v&&v.paused) v.play();",
                completionHandler: nil
            )
        }
    }

    deinit {
        trackingTimer?.invalidate()
        urlObservation?.invalidate()
        sessionTimer?.invalidate()
    }

    // MARK: - Navigation Actions

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
    
    /// Performs a YouTube search with the given query.
    func search(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURLString = "https://m.youtube.com/results?search_query=\(encodedQuery)"
        if let url = URL(string: searchURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    /// Adds or removes the bottom padding on the page depending on toolbar visibility.
    func setBottomMargin(visible: Bool) {
        let px = visible ? "60px" : "0px"
        webView.evaluateJavaScript("document.body.style.paddingBottom = '\(px)';", completionHandler: nil)
    }

    // MARK: - Video Save (Always Enabled)

    /// Saves the current page. Tries JS extraction first, then falls back to URL parsing.
    func saveCurrentVideo() {
        // Strategy A: JS extraction (multiple strategies inside the script)
        webView.evaluateJavaScript(ScriptInjectionService.videoInfoScript) { [weak self] result, error in
            guard let self = self else { return }

            var videoId: String?
            var title = "Untitled"
            var currentTime: Double = 0
            var duration: Double = 0

            // Parse JS result
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let jsVideoId = info["videoId"] as? String ?? ""
                if !jsVideoId.isEmpty {
                    videoId = jsVideoId
                }
                title = info["title"] as? String ?? "Untitled"
                currentTime = info["currentTime"] as? Double ?? 0
                duration = info["duration"] as? Double ?? 0
            }

            // Strategy B: parse webView.url directly (Swift-side)
            if videoId == nil || videoId!.isEmpty {
                videoId = self.extractVideoIdFromSwift()
            }

            // Strategy C: parse the raw href returned by JS
            if videoId == nil || videoId!.isEmpty,
               let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawURL = info["url"] as? String {
                videoId = self.extractVideoId(from: rawURL)
            }

            // If we found a video ID, save it
            if let vid = videoId, !vid.isEmpty {
                if title.isEmpty || title == "Untitled" || title == "YouTube" {
                    title = "Video \(vid)"
                }

                let video = SavedVideo(
                    id: vid,
                    title: title,
                    thumbnailURL: SavedVideo.thumbnailURL(for: vid),
                    url: "https://m.youtube.com/watch?v=\(vid)",
                    lastTime: currentTime,
                    duration: duration,
                    dateAdded: Date()
                )

                self.storage.save(video)

                DispatchQueue.main.async {
                    self.showSavedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.showSavedFeedback = false
                    }
                }
            } else {
                // All strategies failed — show error popup
                DispatchQueue.main.async {
                    self.saveErrorMessage = "Could not detect a video on this page.\n\nMake sure you are on a YouTube video page (not the home feed).\n\nCurrent URL: \(self.webView.url?.absoluteString ?? "unknown")"
                    self.showSaveError = true
                }
            }
        }
    }

    // MARK: - Swift-side Video ID Extraction

    /// Extracts video ID from the current webView URL using Swift.
    private func extractVideoIdFromSwift() -> String? {
        guard let url = webView.url else { return nil }
        return extractVideoId(from: url.absoluteString)
    }

    /// Extracts a YouTube video ID from any URL string.
    private func extractVideoId(from urlString: String) -> String? {
        // Pattern 1: ?v=XXXXXXXXXXX
        if let range = urlString.range(of: "[?&]v=([a-zA-Z0-9_-]{11})", options: .regularExpression) {
            let match = urlString[range]
            let id = match.dropFirst(3) // drop ?v= or &v=
            return String(id)
        }

        // Pattern 2: youtu.be/XXXXXXXXXXX
        if let range = urlString.range(of: "youtu\\.be/([a-zA-Z0-9_-]{11})", options: .regularExpression) {
            let match = urlString[range]
            let parts = match.split(separator: "/")
            if parts.count >= 2 { return String(parts[1]) }
        }

        // Pattern 3: /embed/XXXXXXXXXXX
        if let range = urlString.range(of: "/embed/([a-zA-Z0-9_-]{11})", options: .regularExpression) {
            let match = urlString[range]
            let parts = match.split(separator: "/")
            if let last = parts.last { return String(last) }
        }

        return nil
    }

    // MARK: - Resume

    /// Opens a saved video and seeks to the stored timestamp.
    func openVideo(_ video: SavedVideo) {
        pendingSeekTime = video.lastTime
        if let url = URL(string: video.url) {
            webView.load(URLRequest(url: url))
        }
    }

    /// Called by the navigation delegate after page load to perform pending seek.
    func performPendingSeek() {
        guard let seekTime = pendingSeekTime, seekTime > 0 else { return }
        pendingSeekTime = nil

        // Wait for the video player to initialise
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.webView.evaluateJavaScript(
                ScriptInjectionService.seekScript(to: seekTime),
                completionHandler: nil
            )
        }
    }

    // MARK: - Auto Tracking

    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Session Timer
    
    private func startSessionTimer() {
        sessionStartTime = Date()
        sessionProgress = 0.0
        
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSessionProgress()
        }
    }
    
    private func updateSessionProgress() {
        guard let startTime = sessionStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        sessionProgress = min(1.0, elapsed / AppConstants.sessionMaxDuration)
    }

    private func startObservingVideoPage() {
        webViewState.$isOnVideoPage
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnVideo in
                if isOnVideo {
                    self?.startTracking()
                } else {
                    self?.stopTracking()
                }
            }
            .store(in: &cancellables)
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.trackProgress()
        }
    }

    private func stopTracking() {
        trackProgress()
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func trackProgress() {
        guard webViewState.isOnVideoPage, !webViewState.currentVideoId.isEmpty else { return }

        webView.evaluateJavaScript(ScriptInjectionService.videoInfoScript) { [weak self] result, error in
            guard let self = self,
                  let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            let videoId = info["videoId"] as? String ?? self.extractVideoIdFromSwift() ?? ""
            let currentTime = info["currentTime"] as? Double ?? 0
            let duration = info["duration"] as? Double ?? 0

            guard !videoId.isEmpty, currentTime > 0 else { return }

            let existing = self.storage.loadAll()
            if var video = existing.first(where: { $0.id == videoId }) {
                video.lastTime = currentTime
                if duration > 0 { video.duration = duration }
                self.storage.save(video)
            }
        }
    }
}
