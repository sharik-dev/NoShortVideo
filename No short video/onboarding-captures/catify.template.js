// Captures de l'onboarding : miniatures et titres -> chats. Le reste est la vraie page.
(function () {
  if (window.__catify) return; window.__catify = true;
  var THUMBS = __THUMBS__, ALBUMS = __ALBUMS__;
  var fr = (navigator.language || "en").toLowerCase().indexOf("fr") === 0;
  var TITLES = fr ? [
    "Mon chat refuse de regarder des Shorts (documentaire complet)",
    "Chef Moustache cuisine des pâtes — 45 min en direct",
    "L'ascension du Mont Miaou — randonnée intégrale",
    "Routine muscu de chaton : aucun raccourci",
        "Pluie & ronrons — 8 heures, zéro pub"
  ] : [
    "My cat refuses to watch Shorts (full documentary)",
    "Chef Whiskers cooks pasta — 45 min live",
    "Climbing Mount Meowtain — the full hike",
    "Kitten gym routine: no shortcuts",
        "Rain & purring — 8 hours, zero ads"
  ];
  var SONGS = fr ? [["Long Ronron (No Short Mix)", "Les Chats Noirs"], ["Sonate au Clair de Lune", "Minou Lofi"]]
                 : [["Long Purr (No Short Mix)", "The Catles"], ["Meownlight Sonata", "Lofi Kitty"]];
  var isMusic = location.host.indexOf("music.") === 0;
  // Chaque vidéo de capture a son titre et son chat (même index dans les deux listes).
  var PICK = { "aqz-KE-bpKQ": 4, "jNQXAC9IVRw": 1 };
  var vid = (location.search.match(/[?&]v=([^&]+)/) || [])[1];
  var off = PICK[vid] || 0;
  var n = off + 1, tn = 0;

  function leaf(el) { while (el && el.children && el.children.length === 1) el = el.children[0]; return el; }
  function setText(el, t) { var l = leaf(el); if (l && l.textContent !== t) l.textContent = t; }

  function swapImg(img) {
    var src = (img.currentSrc || img.src || "") + " " + (img.getAttribute("srcset") || "");
    if (img.dataset.cat) return;
    var art = /ytimg\.com\/vi|i\d?\.ytimg|lh3\.googleusercontent|googleusercontent\.com\/[^ ]*=w/.test(src);
    if (!art || /yt3\.ggpht|\/a\//.test(src)) return;
    var pool = isMusic ? ALBUMS : THUMBS;
    img.dataset.cat = "1";
    img.removeAttribute("srcset");
    img.src = pool[(n++) % pool.length];
    img.style.objectFit = "cover";
  }

  function run() {
    document.querySelectorAll("img").forEach(swapImg);
    // Vidéo en lecture : une image de chat par-dessus.
    document.querySelectorAll("video").forEach(function (v) {
      if (v.id === "__catvideo") return;
      var box = v.closest(".html5-video-player") || v.parentElement;
      v.style.opacity = "0";
      if (!box || box.querySelector(".__catposter")) return;
      var p = document.createElement("img");
      p.className = "__catposter"; p.src = isMusic ? ALBUMS[0] : THUMBS[off % THUMBS.length];
      p.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:cover;z-index:0;pointer-events:none";
      if (getComputedStyle(box).position === "static") box.style.position = "relative";
      box.insertBefore(p, box.firstChild);
    });
    document.querySelectorAll(".caption-window,.ytp-caption-window-container,.captions-text").forEach(function (e) { e.style.display = "none"; });
    if (!isMusic) {
      var heads = document.querySelectorAll(".media-item-headline, .compact-media-item-headline, h3.large-media-item-headline, .slim-video-information-title, .slim-video-metadata-title, ytm-slim-video-information-renderer h2, .video-card-title");
      tn = off; heads.forEach(function (h) { setText(h, TITLES[(tn++) % TITLES.length]); });
    } else {
      document.querySelectorAll(".song-title, ytmusic-player-page .title, .ytmusic-player-bar.title, yt-formatted-string.title").forEach(function (e, i) {
        setText(e, SONGS[0][0]);
      });
      document.querySelectorAll(".byline, .subtitle, .ytmusic-player-bar.byline").forEach(function (e, i) {
        setText(e, SONGS[0][1]);
      });
    }
  }
  // Page vidéo : une vraie vidéo de chat, placée en tête du document pour que
  // le bouton PiP de l'app (document.querySelector('video')) la prenne, elle.
  if (!isMusic && vid && !document.getElementById("__catvideo")) {
    var cv = document.createElement("video");
    cv.id = "__catvideo"; cv.src = "__CATVIDEO__"; cv.loop = true; cv.muted = true;
    cv.playsInline = true; cv.setAttribute("playsinline", ""); cv.autoplay = true;
    cv.style.cssText = "position:absolute;left:0;top:0;width:10px;height:10px;object-fit:cover;background:#000;z-index:2147483000;pointer-events:none";
    var mount = function () {
      if (!document.body) return setTimeout(mount, 100);
      document.body.insertBefore(cv, document.body.firstChild);
      cv.play().catch(function () {});
    };
    mount();
    setInterval(function () {
      document.querySelectorAll("video").forEach(function (v) { if (v !== cv && !v.paused) v.pause(); });
      if (cv.paused) cv.play().catch(function () {});
      // Posée exactement sur le lecteur de la page.
      var pl = document.querySelector(".html5-video-player, #player-container-id, ytm-player");
      if (pl) {
        var r = pl.getBoundingClientRect();
        cv.style.left = (r.left + scrollX) + "px"; cv.style.top = (r.top + scrollY) + "px";
        cv.style.width = r.width + "px"; cv.style.height = r.height + "px";
      }
    }, 300);
  }
  var artURL = null;
  if (isMusic) fetch(ALBUMS[0]).then(function (r) { return r.blob(); }).then(function (b) { artURL = URL.createObjectURL(b); });
  var runBase = run;
  run = function () {
    runBase();
    if (isMusic && navigator.mediaSession && window.MediaMetadata) {
      var m = navigator.mediaSession.metadata;
      if (!m || m.title !== SONGS[0][0] || (artURL && m.artwork && m.artwork[0] && m.artwork[0].src !== artURL)) {
        navigator.mediaSession.metadata = new MediaMetadata({ title: SONGS[0][0], artist: SONGS[0][1], artwork: [{ src: artURL || ALBUMS[0], sizes: "500x500", type: "image/jpeg" }] });
      }
    }
    if (isMusic && document.title.indexOf(SONGS[0][0]) < 0) document.title = SONGS[0][0] + " - YouTube Music";
  };
  run();
  var q=false; new MutationObserver(function () { if (q) return; q=true; setTimeout(function(){ q=false; run(); }, 120); }).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(run, 700);
})();
