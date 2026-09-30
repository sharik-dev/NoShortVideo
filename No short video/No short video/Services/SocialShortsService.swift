//
//  SocialShortsService.swift
//  No short video
//

import WebKit

/// Étend la seule promesse de l'app — pas de vidéo courte — aux trois réseaux
/// ajoutés à l'écran d'accueil.
///
/// Les Reels d'Instagram, l'onglet vidéo immersive de X et le fil vidéo de
/// LinkedIn disparaissent, exactement comme les Shorts sur YouTube. Le fil, les
/// stories, la navigation, les messages : tout le reste est laissé intact. Une
/// version précédente masquait aussi le fil et les stories — c'était une autre
/// app, pas celle-ci.
///
/// Seule exception au principe « rien d'autre que les vidéos courtes » : la
/// grille de publications suggérées sous la recherche Instagram, qui est un fil
/// infini déguisé (voir `hideExploreSuggestions`).
///
/// Une seule WKWebView passe de YouTube à Instagram à X, donc le script est
/// injecté partout et choisit sa plateforme à l'exécution depuis
/// `location.hostname`. Ailleurs il ressort immédiatement.
///
/// ## Pourquoi on ne fait pas `display: none`
///
/// La première version masquait chaque reel avec `display: none`. Sur un fil
/// infini c'est un piège : la hauteur du document cesse de croître, le lecteur
/// arrive au bas de page à chaque lot chargé, Instagram enchaîne les requêtes
/// et finit par ne plus rien renvoyer — le fil « coupe » au bout de quelques
/// écrans. Ici on **garde toujours la place** occupée par le contenu retiré :
/// une carte repliée dans le fil, `visibility: hidden` dans les grilles. Le
/// défilement reste celui d'Instagram, seul le contenu part.
enum SocialShortsService {

    /// Script permanent, posé à document-end comme `ScriptInjectionService`.
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
        if (window._nsvSocialShorts) {
            window._nsvSocialShorts.apply();
            return;
        }

        var host = (location.hostname || '').toLowerCase();
        function on(domain) { return host === domain || host.endsWith('.' + domain); }

        var platform = null;
        if (on('instagram.com'))                    platform = 'instagram';
        else if (on('x.com') || on('twitter.com'))  platform = 'x';
        else if (on('linkedin.com'))                platform = 'linkedin';
        if (!platform) return;

        var LABEL = (navigator.language || 'en').toLowerCase().indexOf('fr') === 0
            ? 'Vidéo courte masquée'
            : 'Short video hidden';

        // ── Feuille de style, posée une fois ──────────────────────────
        function installStyle() {
            if (document.getElementById('_nsv_social_style')) return;
            var s = document.createElement('style');
            s.id = '_nsv_social_style';
            s.textContent = [
                '._nsv-gone { display: none !important; }',
                // Garde la place : c'est ce qui laisse le fil infini respirer.
                '._nsv-blank { visibility: hidden !important; pointer-events: none !important; }',
                '._nsv-slot {',
                '  min-height: 84px !important;',
                '  display: flex !important;',
                '  align-items: center !important;',
                '  justify-content: center !important;',
                '  margin: 10px 0 !important;',
                '  border: 1px dashed rgba(142,142,147,0.35) !important;',
                '  border-radius: 14px !important;',
                '  color: rgba(142,142,147,0.9) !important;',
                '  font-size: 13px !important;',
                '  font-family: -apple-system, system-ui, sans-serif !important;',
                '}'
            ].join('\\n');
            (document.head || document.documentElement).appendChild(s);
        }

        // Masque en conservant la boîte. Utilisé dans les grilles (Explorer,
        // profils), où chaque vignette a une taille imposée par la grille :
        // la retirer décalerait toute la mise en page.
        function blank(el) {
            if (el && !el.classList.contains('_nsv-blank')) {
                el.classList.add('_nsv-blank');
            }
        }

        // Replie une carte du fil sur une étiquette de 84 px. On vide ses
        // enfants plutôt que la carte elle-même : la carte reste dans le flux,
        // donc le fil continue de s'allonger à mesure qu'on défile.
        function collapse(card) {
            if (!card || card.getAttribute('data-nsv-collapsed') === '1') return;
            card.setAttribute('data-nsv-collapsed', '1');

            var children = card.children;
            for (var i = 0; i < children.length; i++) {
                children[i].classList.add('_nsv-gone');
            }
            var slot = document.createElement('div');
            slot.className = '_nsv-slot';
            slot.textContent = LABEL;
            card.appendChild(slot);
        }

        // Une seule redirection par page : appelée depuis un MutationObserver,
        // une affectation de `location.href` répétée relance un chargement à
        // chaque mutation et fige la webview.
        function redirectOnce(to) {
            if (window._nsvRedirected) return;
            window._nsvRedirected = true;
            location.replace(to);
        }

        // ── Instagram : les Reels ─────────────────────────────────────
        function hideInstagram() {
            // Entrée Reels de la barre de navigation et onglets internes : là,
            // `display: none` est sans risque, ce n'est pas du contenu défilant.
            var navEntries = document.querySelectorAll(
                'a[href="/reels/"], a[href^="/reels/"], a[href="/reels"], [aria-label="Reels"]'
            );
            for (var i = 0; i < navEntries.length; i++) {
                var entry = navEntries[i].closest('a') || navEntries[i];
                entry.classList.add('_nsv-gone');
            }

            // Publications de type reel. L'URL d'un reel est /reel/<id>/.
            var inFeed = location.pathname === '/' || location.pathname === '';
            var reelLinks = document.querySelectorAll('a[href*="/reel/"]');
            for (var j = 0; j < reelLinks.length; j++) {
                var link = reelLinks[j];

                // Hors du fil (profil, Explorer, résultats), on ne remonte
                // jamais jusqu'à `article` : sur ces pages un seul `article`
                // enveloppe la grille entière, et la replier viderait la page.
                if (!inFeed) { blank(link); continue; }

                var card = link.closest('article');
                if (card) collapse(card); else blank(link);
            }

            if (/^\\/reels(\\/|$)/.test(location.pathname)) redirectOnce('/');

            hideExploreSuggestions();
        }

        // Sur la page de recherche, Instagram remplit tout l'écran sous le champ
        // avec une grille de publications suggérées — le fil infini d'Explorer
        // sous un autre nom. On vient y chercher un compte, pas se faire
        // reproposer du contenu.
        //
        // Le tri se fait sur la forme du lien : une suggestion pointe vers une
        // publication (/p/… ou /reel/…), un résultat de recherche pointe vers un
        // profil ou un hashtag. Les résultats restent donc intacts.
        function hideExploreSuggestions() {
            if (location.pathname.indexOf('/explore') !== 0) return;

            var posts = document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"]');
            for (var i = 0; i < posts.length; i++) {
                var cell = posts[i].closest('[role="listitem"]') || posts[i];
                cell.classList.add('_nsv-gone');
            }
        }

        // ── X : le lecteur vidéo immersif ─────────────────────────────
        // X n'a pas d'onglet « Shorts » : son équivalent est le plein écran
        // vertical /i/immersive, où l'on enchaîne les vidéos en défilant.
        function hideX() {
            var entries = document.querySelectorAll(
                'a[href*="/i/immersive"], a[href="/i/videos"], a[href^="/i/videos"]'
            );
            for (var i = 0; i < entries.length; i++) {
                var entry = entries[i].closest('a') || entries[i];
                // Le fil de X est virtualisé et mesuré : on garde la boîte.
                blank(entry);
            }

            if (location.pathname.indexOf('/i/immersive') === 0) redirectOnce('/home');
        }

        // ── LinkedIn : le fil vidéo vertical ──────────────────────────
        function hideLinkedIn() {
            // Viser `/video/` n'importe où dans l'URL attrapait aussi les liens
            // sortants de n'importe quel article : on s'en tient au fil vidéo
            // de LinkedIn lui-même.
            var entries = document.querySelectorAll(
                'a[href^="/video/"], a[href*="linkedin.com/video/"], a[href*="/feed/video"]'
            );
            for (var i = 0; i < entries.length; i++) {
                blank(entries[i].closest('a') || entries[i]);
            }

            if (location.pathname.indexOf('/video/') === 0) redirectOnce('/feed/');
        }

        var hideFor = platform === 'instagram' ? hideInstagram
                    : platform === 'x'         ? hideX
                    : hideLinkedIn;

        function apply() {
            if (!document.body) return;
            installStyle();
            hideFor();
        }

        window._nsvSocialShorts = { platform: platform, apply: apply };

        apply();

        // Débouncé, comme le retrait des Shorts : ces trois sites sont des SPA
        // qui rechargent leur contenu en défilant.
        var pending;
        new MutationObserver(function() {
            clearTimeout(pending);
            pending = setTimeout(apply, 120);
        }).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """
}
