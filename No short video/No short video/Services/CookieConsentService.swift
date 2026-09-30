//
//  CookieConsentService.swift
//  No short video
//

import WebKit

/// Accepte automatiquement les bandeaux de cookies, sur tous les sites.
///
/// La règle est volontairement resserrée en deux temps, parce qu'un script qui
/// clique tout seul sur une page est dangereux :
/// 1. on ne cherche un bouton **que** dans un conteneur qui parle de cookies,
///    de consentement ou de confidentialité ;
/// 2. dans ce conteneur seulement, on clique le bouton dont le libellé accepte.
///
/// Un seul clic par page : le drapeau `_nsvConsentDone` est posé avant même le
/// clic, pour qu'un bandeau qui se redessine ne déclenche pas une rafale.
///
/// Pour refuser au lieu d'accepter, il suffit d'échanger `ACCEPT` et `REJECT`
/// dans `click()` — les deux listes sont déjà là.
enum CookieConsentService {

    static func userScript() -> WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            // Les plateformes de consentement vivent souvent dans une iframe.
            forMainFrameOnly: false
        )
    }

    static let source: String = """
    (function() {
        if (window._nsvConsent) return;
        window._nsvConsent = true;

        function normalize(value) {
            return (value || '')
                .toLowerCase()
                .normalize('NFD')
                .replace(/[\\u0300-\\u036f]/g, '')
                .replace(/[’'`]/g, ' ')
                .replace(/\\s+/g, ' ')
                .trim();
        }

        // Le conteneur doit parler de cookies : c'est ce qui empêche le script
        // de cliquer « J'accepte » sur des conditions d'utilisation, un contrat
        // ou un formulaire quelconque.
        var TOPIC = ['cookie', 'consent', 'consentement', 'confidentialite',
                     'vie privee', 'privacy', 'trackers', 'traceurs'];

        // Libellés COMPLETS, comparés à l'identique. Chercher « agree » en
        // sous-chaîne faisait cliquer le lien « User Agreement » du bandeau de
        // LinkedIn, qui quittait la page pour les conditions d'utilisation.
        var ACCEPT = ['accept all cookies', 'accept all', 'accept cookies',
                      'accept', 'allow all cookies', 'allow all', 'i accept',
                      'i agree', 'agree to all', 'got it', 'continue',
                      'tout accepter', 'accepter tout', 'accepter tous les cookies',
                      'accepter les cookies', 'accepter', 'j accepte',
                      'tout autoriser', 'autoriser tous les cookies'];

        // Gardée pour pouvoir basculer en refus sans réécrire le script.
        var REJECT = ['refuse non essential cookies', 'reject all', 'refuse all',
                      'decline all', 'only necessary', 'necessary only', 'reject',
                      'tout refuser', 'refuser tout', 'continuer sans accepter',
                      'refuser les cookies non essentiels'];

        // Le libellé du bouton doit être l'un de ces textes, pas le contenir :
        // un bandeau de cookies est plein de liens dont le texte englobe un mot
        // d'acceptation (« User Agreement », « Politique d'acceptation »…).
        function isLabel(text, phrases) {
            if (!text) return false;
            for (var i = 0; i < phrases.length; i++) {
                if (text === phrases[i]) return true;
            }
            return false;
        }

        // Pour repérer le CONTENEUR, en revanche, la sous-chaîne est le bon
        // outil : on cherche un thème dans un bloc de texte.
        function mentions(text, phrases) {
            if (!text) return false;
            for (var i = 0; i < phrases.length; i++) {
                if (text.indexOf(phrases[i]) !== -1) return true;
            }
            return false;
        }

        function isVisible(el) {
            var rect = el.getBoundingClientRect();
            if (rect.width < 1 || rect.height < 1) return false;
            var style = window.getComputedStyle(el);
            return style.visibility !== 'hidden' && style.display !== 'none';
        }

        // Remonte de quelques niveaux pour trouver le bloc qui parle de cookies.
        function consentContainer(el) {
            var node = el;
            for (var depth = 0; depth < 10 && node && node !== document.body; depth++) {
                if (mentions(normalize(node.textContent).slice(0, 400), TOPIC) ||
                    mentions(normalize(node.getAttribute && node.getAttribute('id')), TOPIC) ||
                    mentions(normalize(node.className && node.className.toString()), TOPIC)) {
                    return node;
                }
                node = node.parentElement;
            }
            return null;
        }

        function click() {
            // Pas de `a[href]` : accepter des cookies est toujours un bouton.
            // Un lien, lui, emmène ailleurs — c'est ce qui nous expédiait sur
            // les conditions d'utilisation de LinkedIn.
            var actions = document.querySelectorAll(
                'button, [role="button"], input[type="submit"], input[type="button"]'
            );
            for (var i = 0; i < actions.length; i++) {
                var el = actions[i];
                if (!isVisible(el)) continue;
                if (el.tagName === 'A' && el.getAttribute('href') &&
                    el.getAttribute('href') !== '#') continue;

                var label = normalize(el.textContent || el.value ||
                                      (el.getAttribute && el.getAttribute('aria-label')));
                if (!isLabel(label, ACCEPT)) continue;
                if (!consentContainer(el)) continue;

                // Poser le drapeau avant de cliquer : le clic redessine souvent
                // la page et relancerait l'observateur dans la foulée.
                window._nsvConsentDone = true;
                el.click();
                return true;
            }
            return false;
        }

        function run() {
            if (window._nsvConsentDone || !document.body) return;
            if (click()) stop();
        }

        var observer, pending, deadline;
        function stop() {
            if (observer) observer.disconnect();
            clearTimeout(pending);
            clearTimeout(deadline);
        }

        run();

        observer = new MutationObserver(function() {
            clearTimeout(pending);
            pending = setTimeout(run, 150);
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });

        // Au-delà de 15 s le bandeau ne viendra plus : on arrête de surveiller
        // plutôt que de laisser un observateur tourner sur toute la session.
        deadline = setTimeout(stop, 15000);
    })();
    """
}
