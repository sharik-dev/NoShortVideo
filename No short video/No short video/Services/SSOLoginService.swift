//
//  SSOLoginService.swift
//  No short video
//

import WebKit

/// Masque les boutons de connexion par SSO (« Continuer avec Google / Apple /
/// Facebook »), sur tous les sites.
///
/// Ils ne peuvent pas marcher ici : ces flux passent par une fenêtre popup ou
/// une redirection vers le domaine du fournisseur, que Google en particulier
/// refuse de servir à un navigateur embarqué. Les laisser visibles, c'est
/// proposer un chemin qui finit sur une page blanche ou un refus — mieux vaut
/// ne montrer que la connexion par e-mail, qui se fait sur place.
///
/// La règle vise la forme « <verbe> with <fournisseur> » plutôt que des classes
/// CSS, qui changent à chaque déploiement. Elle ne touche donc pas au bouton
/// « Sign in » d'un site, seulement aux raccourcis vers un tiers.
enum SSOLoginService {

    static func userScript() -> WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    static let source: String = """
    (function() {
        if (window._nsvSSO) {
            window._nsvSSO.apply();
            return;
        }

        // Sur le domaine du fournisseur lui-même, ces libellés désignent la
        // vraie page de connexion : on n'y touche pas.
        var host = (location.hostname || '').toLowerCase();
        var PROVIDER_HOSTS = ['accounts.google.com', 'appleid.apple.com',
                              'facebook.com', 'login.microsoftonline.com'];
        for (var h = 0; h < PROVIDER_HOSTS.length; h++) {
            if (host === PROVIDER_HOSTS[h] || host.endsWith('.' + PROVIDER_HOSTS[h])) return;
        }

        function normalize(value) {
            return (value || '')
                .toLowerCase()
                .normalize('NFD')
                .replace(/[\\u0300-\\u036f]/g, '')
                .replace(/[’'`]/g, ' ')
                .replace(/\\s+/g, ' ')
                .trim();
        }

        var PHRASES = [
            'continue with google', 'continue with apple', 'continue with facebook',
            'continue with microsoft', 'continue with github', 'continue with x',
            'sign in with google', 'sign in with apple', 'sign in with facebook',
            'sign up with google', 'sign up with apple', 'log in with google',
            'log in with apple', 'log in with facebook',
            'continuer avec google', 'continuer avec apple', 'continuer avec facebook',
            'se connecter avec google', 'se connecter avec apple',
            'se connecter avec facebook', 'connexion avec google',
            's inscrire avec google', 's inscrire avec apple'
        ];

        function looksLikeSSO(el) {
            var text = normalize(el.textContent || (el.getAttribute && el.getAttribute('aria-label')));
            if (!text || text.length > 45) return false;
            for (var i = 0; i < PHRASES.length; i++) {
                if (text.indexOf(PHRASES[i]) !== -1) return true;
            }
            return false;
        }

        function hide(el) {
            if (el) el.style.setProperty('display', 'none', 'important');
        }

        function apply() {
            if (!document.body) return;

            var actions = document.querySelectorAll('button, [role="button"], a');
            for (var i = 0; i < actions.length; i++) {
                if (!looksLikeSSO(actions[i])) continue;

                // Remonter d'un cran tant que le parent n'enveloppe que ce
                // bouton : sinon on laisse une case vide à la place.
                var el = actions[i];
                for (var depth = 0; depth < 3; depth++) {
                    var parent = el.parentElement;
                    if (!parent || parent === document.body) break;
                    if (parent.children.length !== 1) break;
                    el = parent;
                }
                hide(el);
            }

            // Widgets déposés par le fournisseur (bouton Google « One Tap »,
            // bouton Apple officiel) : ils n'ont pas de texte à nous.
            var widgets = document.querySelectorAll(
                'iframe[src*="accounts.google.com/gsi"], #credential_picker_container, ' +
                '.g_id_signin, [id^="appleid-signin"], iframe[src*="appleid.apple.com/auth"]'
            );
            for (var j = 0; j < widgets.length; j++) hide(widgets[j]);
        }

        window._nsvSSO = { apply: apply };
        apply();

        var pending;
        new MutationObserver(function() {
            clearTimeout(pending);
            pending = setTimeout(apply, 100);
        }).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """
}
