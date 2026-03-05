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

    // MARK: - Combined

    /// All injection scripts combined.
    static var allScripts: String {
        hideShortsScript + "\n" + hideAdsScript
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
