//
//  AdSkipService.swift
//  No short video
//

import WebKit

/// Supprime les annonces de YouTube **et de YouTube Music**.
///
/// Deux couches, dans cet ordre d'importance :
///
/// ## 1. La réponse du lecteur, avant qu'elle n'atteigne le lecteur
///
/// C'est la couche qui fait le travail. Le lecteur HTML5 de YouTube apprend
/// qu'il doit jouer une annonce par le JSON que lui renvoie
/// `/youtubei/v1/player` : les clés `adPlacements`, `playerAds` et `adSlots` y
/// décrivent le pré-roll, les mid-rolls et les encarts. Ces clés retirées, le
/// lecteur ne sait tout simplement pas qu'il y avait une annonce à jouer : il
/// enchaîne sur la vidéo ou le morceau. Rien n'est bloqué au réseau, donc rien
/// ne ressemble à un bloqueur vu de chez Google — c'est ce qui fait la
/// différence avec l'approche par `WKContentRuleList`, qui, elle, déclenchait
/// la contre-mesure (cf. `AdBlockService`).
///
/// Le script se pose à `atDocumentStart` — avant les scripts de YouTube, sinon
/// la première réponse passe avant nous — et intercepte les trois chemins par
/// lesquels ce JSON arrive :
/// - `JSON.parse`, pour les réponses XHR et les blobs inline ;
/// - `Response.prototype.json`, pour les réponses `fetch` ;
/// - `window.ytInitialPlayerResponse` / `ytInitialData`, écrits en clair dans
///   le HTML de la première page, donc jamais parsés.
///
/// Le nettoyage est délibérément **peu profond** : on ne descend que dans les
/// quelques champs connus. Parcourir récursivement une réponse de lecteur (des
/// mégaoctets) à chaque appel coûterait plus cher que tout le reste de l'app.
///
/// ## 2. Le lecteur lui-même, en dernier recours
///
/// Si une annonce passe quand même (format nouveau, réponse servie autrement),
/// le lecteur pose `ad-showing` / `ad-interrupting` sur son conteneur. Dès que
/// cet état apparaît : on coupe le son, on clique « Passer » s'il est offert,
/// sinon on envoie la lecture à la fin de l'annonce — et si sa durée est encore
/// inconnue, on la joue à 16×, ce qui la liquide en un instant. Le son et la
/// vitesse sont rendus au morceau dès que l'état publicitaire retombe.
///
/// Les bandeaux et encarts promotionnels, qui ne passent pas par le lecteur,
/// sont simplement masqués en CSS.
///
/// Limite assumée : ces noms de clés et de classes appartiennent à YouTube et
/// peuvent changer. Le jour où ils changent, les annonces reviennent — rien ne
/// casse, mais il faudra remettre les sélecteurs à jour.
enum AdSkipService {

    /// Les deux scripts, dans l'ordre où ils doivent être posés.
    static func userScripts() -> [WKUserScript] {
        [
            WKUserScript(
                source: playerResponseSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ),
            WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        ]
    }

    // MARK: - Couche 1 — réponse du lecteur

    static let playerResponseSource: String = """
    (function() {
        var host = (location.hostname || '').toLowerCase();
        function on(d) { return host === d || host.slice(-(d.length + 1)) === ('.' + d); }
        if (!on('youtube.com') && !on('youtu.be') && !on('youtube-nocookie.com')) return;
        if (window._nsvAdStrip) return;
        window._nsvAdStrip = true;

        // Les clés qui décrivent une annonce dans une réponse de lecteur.
        var KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];

        function clean(o) {
            if (!o || typeof o !== 'object') return o;
            try {
                for (var i = 0; i < KEYS.length; i++) {
                    if (o[KEYS[i]] !== undefined) { delete o[KEYS[i]]; }
                }
                // Réponse enveloppée (navigation interne de la SPA).
                if (o.playerResponse) { clean(o.playerResponse); }
                if (o.player && o.player.args) { clean(o.player.args); }
                if (o.playerConfig && o.playerConfig.adConfig) {
                    delete o.playerConfig.adConfig;
                }
                // Certaines réponses annoncent encore un pré-roll ici.
                if (o.playabilityStatus && o.playabilityStatus.adPlacements) {
                    delete o.playabilityStatus.adPlacements;
                }
                // Réponses de navigation : un tableau d'actions, chacune
                // pouvant porter sa propre réponse de lecteur.
                if (Array.isArray(o.onResponseReceivedActions)) {
                    o.onResponseReceivedActions.forEach(clean);
                }
            } catch (e) {}
            return o;
        }

        // ── JSON.parse : XHR et blobs inline ──
        try {
            var origParse = JSON.parse;
            JSON.parse = function() {
                return clean(origParse.apply(this, arguments));
            };
        } catch (e) {}

        // ── fetch : Response.json() ──
        try {
            var origJson = Response.prototype.json;
            Response.prototype.json = function() {
                return origJson.apply(this, arguments).then(clean);
            };
        } catch (e) {}

        // ── Variables globales écrites en clair dans le HTML ──
        // Elles ne passent par aucun parseur : il faut les intercepter à
        // l'écriture. L'accesseur est `configurable` pour ne rien casser si
        // YouTube les redéfinit lui-même.
        ['ytInitialPlayerResponse', 'ytInitialData'].forEach(function(name) {
            try {
                var value;
                Object.defineProperty(window, name, {
                    configurable: true,
                    enumerable: true,
                    get: function() { return value; },
                    set: function(v) { value = clean(v); }
                });
            } catch (e) {}
        });
    })();
    """

    // MARK: - Couche 2 — le lecteur

    static let source: String = """
    (function() {
        if (window._nsvAdSkip) return;

        var host = (location.hostname || '').toLowerCase();
        if (host !== 'youtube.com' && host.indexOf('.youtube.com') === -1
            && host !== 'youtu.be') return;

        window._nsvAdSkip = true;

        // Bannières et encarts promotionnels, qui ne passent pas par le
        // lecteur : purement cosmétiques, retirés en CSS.
        function installStyle() {
            if (document.getElementById('_nsv_adskip_style')) return;
            var s = document.createElement('style');
            s.id = '_nsv_adskip_style';
            s.textContent = [
                '.ytp-ad-overlay-container, .ytp-ad-message-container,',
                '.ytp-ad-image-overlay, .video-ads, .ytp-ad-module,',
                'ytmusic-mealbar-promo-renderer,',
                'ytmusic-statement-banner-renderer,',
                'ytm-promoted-sparkles-web-renderer, ytm-promoted-video-renderer,',
                'ytm-companion-ad-renderer, ytd-banner-promo-renderer,',
                '#player-ads, ytd-ad-slot-renderer, ytm-ad-slot-renderer {',
                '  display: none !important;',
                '}'
            ].join('\\n');
            (document.head || document.documentElement).appendChild(s);
        }

        function restore(v) {
            if (!v || !v._nsvAdTouched) return;
            v.muted = v._nsvWasMuted === true;
            v.playbackRate = v._nsvWasRate || 1;
            v._nsvAdTouched = false;
        }

        function tick() {
            var player = document.querySelector('.html5-video-player');
            var video  = (player && player.querySelector('video'))
                       || document.querySelector('video');
            if (!player || !video) return;

            var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting');

            if (!isAd) { restore(video); return; }

            // Mémoriser l'état du morceau une seule fois, avant d'y toucher :
            // rendre le son à la fin d'une annonce ne doit pas démuter un
            // lecteur que l'utilisateur avait lui-même coupé.
            if (!video._nsvAdTouched) {
                video._nsvAdTouched = true;
                video._nsvWasMuted  = video.muted;
                video._nsvWasRate   = video.playbackRate || 1;
            }
            video.muted = true;

            var skip = player.querySelector(
                '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-skip-button-slot button'
            );
            if (skip) { skip.click(); return; }

            if (isFinite(video.duration) && video.duration > 0) {
                // Aller à la fin termine l'annonce et enchaîne sur le contenu.
                video.currentTime = video.duration;
            } else {
                // Durée encore inconnue : on la brûle en accéléré.
                video.playbackRate = 16;
            }
        }

        installStyle();
        tick();
        setInterval(tick, 400);
    })();
    """
}
