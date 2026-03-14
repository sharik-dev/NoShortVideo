//
//  ScriptInjectionService.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import WebKit

/// Provides JavaScript snippets injected into the YouTube web view.
enum ScriptInjectionService {

    // MARK: - Shorts Removal

    /// Hides Shorts shelves, tabs, and related UI from the YouTube page.
    /// Uses a MutationObserver so dynamically‑loaded content is also caught.
    static var hideShortsScript: String {
        """
        (function() {
            function removeShorts() {
                // ── Desktop selectors ──
                document.querySelectorAll('ytd-reel-shelf-renderer').forEach(e => e.remove());
                document.querySelectorAll('ytd-rich-section-renderer').forEach(e => {
                    if (e.innerText.includes('Shorts')) e.remove();
                });
                document.querySelectorAll('[title="Shorts"]').forEach(e => {
                    var parent = e.closest('ytd-guide-entry-renderer') || e.closest('ytd-mini-guide-entry-renderer');
                    if (parent) parent.remove();
                });

                // ── Mobile selectors ──
                // Shorts shelf
                document.querySelectorAll('ytm-reel-shelf-renderer').forEach(e => e.remove());
                // Shorts tab in bottom nav
                document.querySelectorAll('ytm-pivot-bar-item-renderer').forEach(e => {
                    if (e.innerText.includes('Shorts')) e.style.display = 'none';
                });
                document.querySelectorAll('a[href="/shorts"]').forEach(e => {
                    var item = e.closest('ytm-pivot-bar-item-renderer') || e.parentElement;
                    if (item) item.style.display = 'none';
                });

                // ── Individual Shorts recommendations ──
                // Any link pointing to a /shorts/ video — hide the whole card
                document.querySelectorAll('a[href*="/shorts/"]').forEach(e => {
                    var card = e.closest('ytm-video-with-context-renderer')
                            || e.closest('ytm-compact-video-renderer')
                            || e.closest('ytm-rich-item-renderer')
                            || e.closest('ytd-video-renderer')
                            || e.closest('ytd-compact-video-renderer')
                            || e.closest('ytd-rich-item-renderer')
                            || e.closest('ytd-grid-video-renderer');
                    if (card) {
                        card.style.display = 'none';
                    } else {
                        e.style.display = 'none';
                    }
                });

                // Mobile Shorts lockup renderers
                document.querySelectorAll('ytm-shorts-lockup-view-model').forEach(e => e.remove());
                document.querySelectorAll('ytm-shorts-lockup-view-model-v2').forEach(e => e.remove());

                // Shorts badge overlay items
                document.querySelectorAll('[overlay-style="SHORTS"]').forEach(e => {
                    var card = e.closest('ytm-video-with-context-renderer')
                            || e.closest('ytm-compact-video-renderer')
                            || e.closest('ytd-video-renderer')
                            || e.closest('ytd-compact-video-renderer');
                    if (card) card.style.display = 'none';
                });

                // Generic fallback
                document.querySelectorAll('[is-shorts]').forEach(e => e.remove());

                // Redirect: if the user somehow lands on a /shorts/ page, go home
                if (window.location.pathname.startsWith('/shorts')) {
                    window.location.href = '/';
                }
            }

            removeShorts();

            var observer = new MutationObserver(function() { removeShorts(); });
            observer.observe(document.body, { childList: true, subtree: true });
        })();
        """
    }

    // MARK: - Ad Hiding

    /// Best‑effort removal of ad containers on YouTube.
    static var hideAdsScript: String {
        """
        (function() {
            function removeAds() {
                var selectors = [
                    'ytd-ad-slot-renderer',
                    'ytm-promoted-sparkles-web-renderer',
                    'ytm-companion-ad-renderer',
                    '#player-ads',
                    'ytd-banner-promo-renderer',
                    'ytm-promoted-video-renderer'
                ];
                selectors.forEach(function(sel) {
                    document.querySelectorAll(sel).forEach(function(el) { el.remove(); });
                });
            }

            removeAds();

            var observer = new MutationObserver(function() { removeAds(); });
            observer.observe(document.body, { childList: true, subtree: true });
        })();
        """
    }

    /// JavaScript that extracts video metadata using MULTIPLE strategies simultaneously.
    /// At least one should succeed on mobile YouTube SPA.
    static var videoInfoScript: String {
        """
        (function() {
            var videoId = '';
            var title = document.title || '';
            var video = document.querySelector('video');
            var currentTime = video ? video.currentTime : 0;
            var duration = video ? video.duration : 0;

            // Strategy 1: URL search params (?v=...)
            try {
                var p = new URLSearchParams(window.location.search);
                if (p.get('v')) videoId = p.get('v');
            } catch(e) {}

            // Strategy 2: canonical link
            if (!videoId) {
                try {
                    var canon = document.querySelector('link[rel="canonical"]');
                    if (canon) {
                        var m = canon.href.match(/[?&]v=([^&]+)/);
                        if (m) videoId = m[1];
                        if (!videoId) {
                            m = canon.href.match(/\\/watch\\/([^?&/]+)/);
                            if (m) videoId = m[1];
                        }
                    }
                } catch(e) {}
            }

            // Strategy 3: og:url meta tag
            if (!videoId) {
                try {
                    var og = document.querySelector('meta[property="og:url"]');
                    if (og) {
                        var m = og.content.match(/[?&]v=([^&]+)/);
                        if (m) videoId = m[1];
                    }
                } catch(e) {}
            }

            // Strategy 4: og:title for better title
            try {
                var ogTitle = document.querySelector('meta[property="og:title"]');
                if (ogTitle && ogTitle.content) title = ogTitle.content;
            } catch(e) {}

            // Strategy 5: parse full href with regex
            if (!videoId) {
                try {
                    var href = window.location.href;
                    var m = href.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
                    if (m) videoId = m[1];
                    if (!videoId) {
                        m = href.match(/youtu\\.be\\/([a-zA-Z0-9_-]{11})/);
                        if (m) videoId = m[1];
                    }
                } catch(e) {}
            }

            // Strategy 6: ytInitialPlayerResponse
            if (!videoId) {
                try {
                    if (typeof ytInitialPlayerResponse !== 'undefined' && ytInitialPlayerResponse.videoDetails) {
                        videoId = ytInitialPlayerResponse.videoDetails.videoId || '';
                        if (!title || title === 'YouTube') {
                            title = ytInitialPlayerResponse.videoDetails.title || title;
                        }
                    }
                } catch(e) {}
            }

            // Strategy 7: video source URL
            if (!videoId && video && video.src) {
                try {
                    var m = video.src.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
                    if (m) videoId = m[1];
                } catch(e) {}
            }

            // Strategy 8: any link on page that looks like current watch
            if (!videoId) {
                try {
                    var links = document.querySelectorAll('a[href*="watch?v="]');
                    for (var i = 0; i < links.length; i++) {
                        var cl = links[i].closest('.currently-playing, .active, [aria-current]');
                        if (cl) {
                            var m = links[i].href.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
                            if (m) { videoId = m[1]; break; }
                        }
                    }
                } catch(e) {}
            }

            // Clean title
            title = title.replace(' - YouTube', '').replace(' — YouTube', '');

            var result = {
                videoId: videoId,
                title: title,
                currentTime: currentTime,
                duration: duration,
                url: window.location.href,
                hasVideo: !!video
            };
            return JSON.stringify(result);
        })();
        """
    }

    /// JavaScript to seek the video to a specific time.
    static func seekScript(to seconds: Double) -> String {
        """
        (function() {
            var video = document.querySelector('video');
            if (video) {
                video.currentTime = \(seconds);
                video.play();
            }
        })();
        """
    }

    // MARK: - Bottom Margin

    /// Adds bottom padding to the page so the app's floating toolbar
    /// doesn't cover YouTube's native tab bar.
    static var bottomMarginScript: String {
        """
        (function() {
            function addBottomMargin() {
                document.body.style.paddingBottom = '60px';
            }
            addBottomMargin();
            var observer = new MutationObserver(function() { addBottomMargin(); });
            observer.observe(document.body, { childList: true, subtree: true });
        })();
        """
    }

    // MARK: - Background Audio

    /// Injected at document-start so it runs before YouTube's own scripts.
    /// Overrides the Visibility API so YouTube cannot detect the app has been
    /// backgrounded and pause playback.
    static var backgroundAudioScript: String {
        """
        (function() {
            try {
                Object.defineProperty(document, 'visibilityState', {
                    configurable: true,
                    get: function() { return 'visible'; }
                });
                Object.defineProperty(document, 'hidden', {
                    configurable: true,
                    get: function() { return false; }
                });
            } catch(e) {}

            // Stop YouTube's visibilitychange handlers from firing
            document.addEventListener('visibilitychange', function(e) {
                e.stopImmediatePropagation();
            }, true);
            document.addEventListener('webkitvisibilitychange', function(e) {
                e.stopImmediatePropagation();
            }, true);
        })();
        """
    }

    /// Returns a `WKUserScript` injected at document-start for background audio.
    static func backgroundAudioUserScript() -> WKUserScript {
        WKUserScript(
            source: backgroundAudioScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    // MARK: - PiP Overlay Button

    /// Injects a small floating PiP button whenever a video element is present.
    /// Tapping it calls the native requestPictureInPicture() API.
    static var pipOverlayScript: String {
        """
        (function() {
            function injectPipButton() {
                var video = document.querySelector('video');
                if (!video || document.getElementById('_meowtube_pip')) return;
                if (!('requestPictureInPicture' in video)) return;

                var btn = document.createElement('button');
                btn.id = '_meowtube_pip';
                btn.textContent = '⛶';
                btn.style.cssText = [
                    'position:fixed',
                    'bottom:80px',
                    'right:12px',
                    'z-index:2147483647',
                    'width:40px',
                    'height:40px',
                    'border-radius:10px',
                    'background:rgba(0,0,0,0.70)',
                    'color:#fff',
                    'font-size:20px',
                    'border:none',
                    'cursor:pointer',
                    'display:flex',
                    'align-items:center',
                    'justify-content:center',
                    '-webkit-backdrop-filter:blur(6px)',
                    'backdrop-filter:blur(6px)'
                ].join(';');

                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    var v = document.querySelector('video');
                    if (!v) return;
                    if (document.pictureInPictureElement) {
                        document.exitPictureInPicture().catch(function(){});
                    } else {
                        v.requestPictureInPicture().catch(function(){});
                    }
                });
                document.body.appendChild(btn);
            }

            injectPipButton();
            new MutationObserver(injectPipButton)
                .observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
    }

    // MARK: - Combined

    /// All injection scripts combined.
    /// Bottom margin is only added on iPhone where the toolbar sits at the bottom.
    static var allScripts: String {
        var scripts = hideShortsScript + "\n" + hideAdsScript + "\n" + pipOverlayScript
        if UIDevice.current.userInterfaceIdiom == .phone {
            scripts += "\n" + bottomMarginScript
        }
        return scripts
    }

    /// Returns a `WKUserScript` ready to be added to a content controller.
    static func userScript() -> WKUserScript {
        WKUserScript(
            source: allScripts,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }
}
