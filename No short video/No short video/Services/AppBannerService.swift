//
//  AppBannerService.swift
//  No short video
//

import WebKit

/// Retire les bandeaux et boutons « ouvre l'app » sur YouTube, X, Twitch,
/// Instagram et LinkedIn.
///
/// Ces deux sites poussent en permanence leur application native par-dessus le
/// web : un bandeau collé en bas ou en haut, parfois un panneau qui recouvre la
/// page. Dans meowTube c'est une impasse — l'app native est précisément celle
/// qu'on ne veut pas ouvrir.
///
/// Les classes CSS d'Instagram sont générées et changent à chaque déploiement,
/// donc viser `.x1abc2def` ne tiendrait pas une semaine. La règle part plutôt de
/// ce qui, lui, ne change pas : **le texte du bouton**. On cherche un lien ou un
/// bouton dont le libellé propose d'ouvrir l'application, on remonte jusqu'au
/// conteneur épinglé (`position: fixed` ou `sticky`) qui le porte, et on masque
/// ce conteneur.
///
/// Deux garde-fous, parce que la règle est large :
/// - on ne masque jamais un bloc qui contient un champ mot de passe ou e-mail
///   (le mur de connexion d'Instagram ressemble beaucoup à un bandeau) ;
/// - on ne masque jamais un bloc qui couvre plus de 60 % de la hauteur visible,
///   pour ne pas vider la page sur un faux positif.
///
/// Sur YouTube et X, un bouton « Open app » peut aussi être le titre d'une
/// vidéo ou d'un post (« How to open app settings… ») : le texte doit donc
/// ressembler à un bouton (court, proche de la phrase), et tout ce qui vit dans
/// un post (`article`) ou pointe vers une vidéo est ignoré.
///
/// Ajouter un site tient dans la liste `platform` ci-dessous.
enum AppBannerService {

    static func userScript() -> WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    // MARK: - Source

    static let source: String = """
    (function() {
        if (window._nsvAppBanner) {
            window._nsvAppBanner.apply();
            return;
        }

        var host = (location.hostname || '').toLowerCase();
        function on(domain) { return host === domain || host.endsWith('.' + domain); }

        var platform = null;
        if (on('instagram.com')) platform = 'instagram';
        else if (on('twitch.tv')) platform = 'twitch';
        else if (on('youtube.com')) platform = 'youtube';
        else if (on('x.com') || on('twitter.com')) platform = 'x';
        else if (on('linkedin.com')) platform = 'linkedin';
        if (!platform) return;

        // Libellés du bouton, dans les deux langues de l'app.
        var PHRASES = [
            'open the app', 'open in app', 'open in the app', 'open app',
            'use the app', 'continue in the app', 'continue in app',
            'open instagram', 'open in instagram',
            'open in the twitch app', 'watch on the twitch app', 'get the app',
            'get app', 'open youtube', 'open in youtube', 'switch to the app',
            'open x', 'open in x', 'see it in the app', 'view in app',
            'use app', 'use the linkedin app', 'open linkedin', 'open in linkedin',
            'try the app', 'get the linkedin app',
            'ouvrir l application', 'ouvrir dans l application', 'ouvrir l app',
            'utiliser l application', 'continuer dans l application',
            'voir dans l application', 'telecharger l application',
            'ouvrir youtube', 'ouvrir dans youtube', 'obtenir l application',
            'installer l application', 'passer a l application', 'passer a l app',
            'ouvrir x', 'ouvrir dans x', 'voir dans l app', 'utiliser l app',
            'ouvrir linkedin', 'ouvrir dans linkedin', 'utiliser l appli',
            'utiliser l application linkedin'
        ];

        function normalize(value) {
            return (value || '')
                .toLowerCase()
                .normalize('NFD')
                .replace(/[\\u0300-\\u036f]/g, '')
                .replace(/[’'`]/g, ' ')
                .replace(/\\s+/g, ' ')
                .trim();
        }

        function looksLikeAppPrompt(el) {
            var text = normalize(el.textContent);
            // Un bouton, pas un article : au-delà on tomberait sur du contenu
            // qui mentionne l'application en passant.
            if (!text || text.length > 60) return false;
            // Un post X ou une vignette YouTube n'est jamais un bandeau.
            if ((platform === 'youtube' || platform === 'x') && el.closest('article')) return false;
            var href = el.getAttribute('href') || '';
            if (/\\/(watch|shorts|status)\\b/.test(href)) return false;
            for (var i = 0; i < PHRASES.length; i++) {
                var phrase = PHRASES[i];
                var at = (' ' + text + ' ').indexOf(' ' + phrase + ' ');
                // Mot entier, et guère plus long que la phrase elle-même :
                // « Open app » oui, « How to open app settings on iPhone » non.
                if (at !== -1 && text.length <= phrase.length + 12) return true;
            }
            return false;
        }

        function isPinned(el) {
            var position = window.getComputedStyle(el).position;
            return position === 'fixed' || position === 'sticky';
        }

        // Ne jamais emporter un formulaire de connexion ni la moitié de l'écran.
        function isSafeToHide(el) {
            if (el.querySelector('input[type="password"], input[type="email"], input[name*="username" i]')) {
                return false;
            }
            var height = el.getBoundingClientRect().height;
            return height <= window.innerHeight * 0.6;
        }

        function hide(el) {
            if (el && isSafeToHide(el)) {
                el.style.setProperty('display', 'none', 'important');
                return true;
            }
            return false;
        }

        // Un conteneur épinglé n'est pas forcément un bandeau publicitaire :
        // l'en-tête d'Instagram est `sticky` et porte à la fois un bouton
        // « Open app » ET la navigation du site — onglets « For you », cœur des
        // notifications, recherche. Le masquer en bloc emportait toute la barre.
        // Dès qu'un conteneur ressemble à du mobilier de site, on ne retire que
        // le bouton.
        function isSiteChrome(el) {
            if (!el) return false;
            if (el.querySelector('nav, [role="navigation"], [role="tablist"], [role="search"], input')) {
                return true;
            }
            return el.querySelectorAll('a').length >= 3;
        }

        function hideByButtonText() {
            var actions = document.querySelectorAll('a, button, [role="button"]');
            for (var i = 0; i < actions.length; i++) {
                if (!looksLikeAppPrompt(actions[i])) continue;

                // Remonter jusqu'au conteneur épinglé qui porte le bouton.
                var el = actions[i], pinned = null;
                for (var depth = 0; depth < 8 && el && el !== document.body; depth++) {
                    if (isPinned(el)) { pinned = el; break; }
                    el = el.parentElement;
                }

                if (pinned && !isSiteChrome(pinned) && hide(pinned)) continue;
                hide(actions[i]);
            }
        }

        // Crochets explicites, quand ils existent : plus sûrs que le texte.
        function hideKnownContainers() {
            var selectors = {
                twitch: ['[data-a-target="app-banner"]',
                         '[data-a-target="mobile-web-app-banner"]',
                         '[data-a-target="app-install-banner"]',
                         '.app-banner', '.mobile-web-banner'],
                instagram: ['[data-testid="app-banner"]', '[data-testid="open-in-app"]'],
                // « YouTube, c'est mieux dans l'app » collé en bas de page.
                youtube: ['ytm-mealbar-promo-renderer'],
                x: [],
                linkedin: ['.app-banner', '[data-test-id="app-banner"]',
                           '[data-tracking-control-name*="app_upsell"]',
                           '[data-tracking-control-name*="open_app"]']
            }[platform];

            for (var i = 0; i < selectors.length; i++) {
                var found = document.querySelectorAll(selectors[i]);
                for (var j = 0; j < found.length; j++) hide(found[j]);
            }

            // Bandeau natif iOS — inoffensif dans WKWebView, retiré par principe.
            var smart = document.querySelector('meta[name="apple-itunes-app"]');
            if (smart) smart.remove();
        }

        function apply() {
            if (!document.body) return;
            hideKnownContainers();
            hideByButtonText();
        }

        window._nsvAppBanner = { platform: platform, apply: apply };

        apply();

        // Les deux sites réinjectent le bandeau au fil de la navigation interne.
        var pending;
        new MutationObserver(function() {
            clearTimeout(pending);
            pending = setTimeout(apply, 120);
        }).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """
}
