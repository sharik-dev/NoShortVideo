//
//  MusicPriorityService.swift
//  No short video
//

import WebKit

/// La musique passe avant les vidéos des réseaux sociaux.
///
/// Sur Instagram ou X, une vidéo qui démarre avec du son réclame l'audio : iOS
/// coupe alors la musique (YouTube Music comme les MP3 hors ligne), et elle ne
/// repart qu'une fois la vidéo finie — c'est-à-dire jamais, dans un fil qui
/// enchaîne les vidéos.
///
/// Parade : tant qu'un morceau joue, **toutes les vidéos de ces pages sont
/// muettes**. Elles défilent normalement, mais sans son, WebKit n'a aucune
/// raison de prendre l'audio. Un appui sur « son » dans le lecteur du site est
/// aussitôt annulé — mettre la musique en pause rend la main au site.
///
/// Rien n'est « démuté » quand la musique s'arrête : on cesse simplement
/// d'imposer le silence, et le site retrouve son comportement normal (vidéos
/// muettes par défaut, son au toucher).
enum MusicPriorityService {

    /// Installé dans chaque page, à l'ouverture. Ne fait rien tant que
    /// `__nsvSetMusicMute(true)` n'a pas été appelé.
    static func userScript() -> WKUserScript {
        WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    /// Active ou lève le silence imposé dans la page.
    static func setMutedScript(_ muted: Bool) -> String {
        "window.__nsvSetMusicMute && window.__nsvSetMusicMute(\(muted));"
    }

    private static let script = """
    (function() {
        if (window.__nsvSetMusicMute) return;
        var active = false;

        function hush(el) {
            if (active && el && !el.muted) el.muted = true;
        }

        // Avant même que la lecture démarre : sinon on entendrait le premier
        // quart de seconde.
        var nativePlay = HTMLMediaElement.prototype.play;
        HTMLMediaElement.prototype.play = function() {
            hush(this);
            return nativePlay.apply(this, arguments);
        };

        // Filet : lecture lancée autrement, ou son réactivé par le site.
        ['play', 'playing', 'volumechange', 'loadedmetadata'].forEach(function(type) {
            document.addEventListener(type, function(e) {
                if (e.target instanceof HTMLMediaElement) hush(e.target);
            }, true);
        });

        window.__nsvSetMusicMute = function(on) {
            active = !!on;
            if (active) document.querySelectorAll('video, audio').forEach(hush);
        };
    })();
    """
}
