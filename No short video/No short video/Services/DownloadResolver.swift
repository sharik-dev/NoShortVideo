//
//  DownloadResolver.swift
//  No short video
//
//  Created by Sharik Mohamed on 30/09/2026.
//

import UIKit
import WebKit

/// Un site convertisseur qu'on pilote en coulisse pour obtenir l'adresse d'un
/// MP4. L'ordre de `allCases` est l'ordre d'essai : ytdown d'abord, YT1s en
/// secours.
enum DownloadProvider: String, CaseIterable {
    case ytdown
    case yt1s

    var displayName: String {
        switch self {
        case .ytdown: return "YTDown"
        case .yt1s:   return "YT1s"
        }
    }

    /// Page chargée dans la webview cachée.
    ///
    /// YT1s : `yt1s.com` a été fermé par l'IFPI, ses miroirs (`yt1s.com.co`,
    /// `yt1s.mx`…) ne font qu'afficher ce widget en iframe. On charge le widget
    /// directement — c'est lui qui fait le travail, et on évite une page de plus
    /// et ses publicités.
    func startURL(videoId: String) -> URL {
        switch self {
        case .ytdown:
            return URL(string: "https://app.ytdown.to/fr38/")!
        case .yt1s:
            return URL(string: "https://embed.dlsrv.online/v1/full?videoId=\(videoId)")!
        }
    }

    /// Domaines où la webview a le droit de naviguer. Tout le reste est une
    /// redirection publicitaire : on l'annule sans rien charger.
    var allowedHosts: [String] {
        switch self {
        case .ytdown: return ["ytdown.to", "challenges.cloudflare.com"]
        case .yt1s:   return ["dlsrv.online"]
        }
    }
}

/// Ce qu'on demande au site : une vidéo MP4 (YouTube) ou un MP3 (YouTube Music).
enum DownloadFormat: String {
    case mp4
    case mp3

    var fileExtension: String { rawValue }
}

/// Ce que le site finit par livrer : un fichier prêt à être téléchargé.
struct ResolvedMedia {
    let fileURL: URL
    let suggestedName: String?
    /// Page d'où vient le lien — renvoyée en `Referer`, certains serveurs de
    /// fichiers refusent sans.
    let referer: URL
    let cookies: [HTTPCookie]
}

enum DownloadResolverError: LocalizedError {
    case timeout
    case site(String)

    var errorDescription: String? {
        switch self {
        case .timeout:          return "timeout"
        case .site(let reason): return reason
        }
    }
}

/// Pilote un convertisseur dans une `WKWebView` invisible : colle le lien,
/// choisit la qualité, attend la conversion, et rend l'adresse du fichier.
///
/// L'utilisateur ne voit jamais le site. On passe par une vraie webview — et
/// non par des requêtes HTTP directes — parce que les deux sites l'exigent :
/// ytdown est derrière un défi Cloudflare, et le widget de YT1s calcule une
/// preuve de travail et refuse les navigateurs automatisés. Une webview
/// ordinaire passe les deux ; il suffit de remplir le formulaire à la place de
/// l'utilisateur.
///
/// La webview est posée dans la fenêtre, par-dessus tout, dans une boîte d'un
/// pixel : hors fenêtre ou recouverte, WebKit gèle les minuteries JavaScript
/// et ni le défi Cloudflare ni la conversion n'aboutissent.
final class DownloadResolver: NSObject {

    private let provider: DownloadProvider
    private let videoId: String
    private let format: DownloadFormat
    private var webView: WKWebView?
    /// Boîte d'un pixel qui porte la webview (cf. `start`).
    private var container: UIView?
    private var continuation: CheckedContinuation<ResolvedMedia, Error>?
    private var watchdog: Timer?
    private var lastActivity = Date()
    private let onProgress: (Double) -> Void

    /// Sans nouvelle du site pendant ce délai, on abandonne. Remis à zéro à
    /// chaque progression : une longue vidéo peut convertir plusieurs minutes,
    /// ce qui compte est que ça avance.
    private let idleTimeout: TimeInterval = 45

    init(provider: DownloadProvider, videoId: String, format: DownloadFormat,
         onProgress: @escaping (Double) -> Void) {
        self.provider = provider
        self.videoId = videoId
        self.format = format
        self.onProgress = onProgress
    }

    func resolve() async throws -> ResolvedMedia {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            start()
        }
    }

    // MARK: - Cycle de vie

    private func start() {
        let config = WKWebViewConfiguration()
        // Magasin par défaut : le jeton Cloudflare y survit d'un téléchargement
        // à l'autre, le défi n'est passé qu'une fois.
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all

        let controller = WKUserContentController()
        controller.add(WeakMessageHandler(self), name: "meowDL")
        controller.addUserScript(WKUserScript(
            source: Self.script(for: provider, videoId: videoId, format: format),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        config.userContentController = controller

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isUserInteractionEnabled = false
        web.customUserAgent = Self.safariUserAgent
        webView = web

        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            // Au-dessus de tout, et non dessous : une webview recouverte est
            // jugée occultée par WebKit, qui étrangle alors ses minuteries — le
            // site cale en pleine conversion. Elle garde sa taille d'écran de
            // téléphone (le site se met en page normalement) mais vit dans une
            // boîte d'un pixel qui la découpe : pour WebKit elle est visible,
            // pour l'œil il n'en reste rien. L'opacité seule laissait un
            // fantôme du site sur les écrans sombres.
            let box = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            box.clipsToBounds = true
            box.alpha = 0.02
            box.isUserInteractionEnabled = false
            box.addSubview(web)
            window.addSubview(box)
            container = box
        }

        web.load(URLRequest(url: provider.startURL(videoId: videoId)))

        lastActivity = Date()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Une feuille ouverte entre-temps passerait par-dessus.
            if let box = self.container { box.superview?.bringSubviewToFront(box) }
            #if DEBUG
            self.webView?.evaluateJavaScript("document.title + ' | ' + document.body.innerText.slice(0,120).replace(/\\s+/g,' ')") { r, _ in
                debugLog("[Download] page: \(r ?? "-")")
            }
            #endif
            if Date().timeIntervalSince(self.lastActivity) > self.idleTimeout {
                self.finish(.failure(DownloadResolverError.timeout))
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<ResolvedMedia, Error>) {
        watchdog?.invalidate()
        watchdog = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "meowDL")
        webView?.removeFromSuperview()
        webView = nil
        container?.removeFromSuperview()
        container = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private func deliver(_ url: URL, name: String?) {
        guard continuation != nil else { return }
        #if DEBUG
        debugLog("[Download] \(provider.displayName) file at \(url.host ?? "?")\(url.path)")
        #endif
        let referer = webView?.url ?? provider.startURL(videoId: videoId)
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            self?.finish(.success(ResolvedMedia(
                fileURL: url, suggestedName: name, referer: referer, cookies: cookies
            )))
        }
    }

    /// Un fichier média, reconnu à son adresse seule — utile avant d'avoir la
    /// réponse du serveur (popup, lien `download`).
    private static func looksLikeMedia(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        return s.contains(".mp4") || s.contains(".mp3") || s.contains("/tunnel") || s.contains("googlevideo.com")
            || url.host?.contains("ytcontent.com") == true
    }

    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

// MARK: - Messages du script

extension DownloadResolver: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        lastActivity = Date()
        #if DEBUG
        if type != "alive" { debugLog("[Download] \(provider.displayName) → \(type) \(body["value"] ?? body["message"] ?? "")") }
        #endif

        switch type {
        case "progress":
            if let value = body["value"] as? Double { onProgress(min(max(value, 0), 1)) }
        case "result":
            if let s = body["url"] as? String, let url = URL(string: s) {
                deliver(url, name: body["name"] as? String)
            }
        case "error":
            finish(.failure(DownloadResolverError.site(body["message"] as? String ?? "error")))
        default:
            break // "alive" : simple signe de vie, déjà compté plus haut
        }
    }
}

// MARK: - Navigation : bloquer la pub, attraper le fichier

extension DownloadResolver: WKNavigationDelegate, WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        #if DEBUG
        if action.targetFrame?.isMainFrame == true { debugLog("[Download] nav \(url.host ?? "?")\(url.path)") }
        #endif

        // Lien de téléchargement déclenché par le site lui-même (le bouton
        // « Download » crée un `<a download>`) : c'est le fichier qu'on veut.
        if action.shouldPerformDownload || Self.looksLikeMedia(url) {
            decisionHandler(.cancel)
            deliver(url, name: nil)
            return
        }

        // Un envoi de formulaire natif veut dire que le site n'a pas intercepté
        // le clic : laisser partir ce POST recharge la page et relance le
        // script — une boucle que Cloudflare finit par bloquer.
        if action.targetFrame?.isMainFrame == true, action.navigationType == .formSubmitted {
            return decisionHandler(.cancel)
        }

        // Les iframes (défi Cloudflare, captcha) passent. La page principale,
        // elle, ne quitte pas le site : une redirection vers ailleurs est une
        // pub.
        if action.targetFrame?.isMainFrame == true,
           let host = url.host?.lowercased(),
           !provider.allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let mime = response.response.mimeType?.lowercased() ?? ""
        if let url = response.response.url,
           mime.hasPrefix("video/") || mime.hasPrefix("audio/")
            || mime == "application/octet-stream" || !response.canShowMIMEType {
            decisionHandler(.cancel)
            deliver(url, name: response.response.suggestedFilename)
            return
        }
        decisionHandler(.allow)
    }

    /// `window.open` : les deux sites ouvrent une pub au premier clic. On ne
    /// crée jamais de fenêtre — sauf à y reconnaître le fichier lui-même.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url, Self.looksLikeMedia(url) {
            deliver(url, name: nil)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(DownloadResolverError.site("web process crashed")))
    }
}

// MARK: - Scripts injectés

extension DownloadResolver {

    /// Le script tourne à chaque chargement de page : le défi Cloudflare
    /// recharge la page une fois passé, et c'est au second passage que le
    /// formulaire existe. Il se contente d'attendre ses éléments.
    static func script(for provider: DownloadProvider, videoId: String, format: DownloadFormat) -> String {
        let common = """
        (function(){
          if (window.__meowDL) return; window.__meowDL = true;
          const VIDEO_ID = '\(videoId)';
          const AUDIO = \(format == .mp3 ? "true" : "false");
          const post = (m) => { try { window.webkit.messageHandlers.meowDL.postMessage(m); } catch(e){} };
          const sleep = (ms) => new Promise(r => setTimeout(r, ms));
          async function waitFor(fn, ms) {
            const end = Date.now() + ms;
            while (Date.now() < end) { const v = fn(); if (v) return v; await sleep(400); post({type:'alive'}); }
            return null;
          }
          // Qualité « standard » : 720p d'abord, puis la plus proche en dessous,
          // puis n'importe quel MP4. Au-delà de 720p, fichiers énormes pour un
          // écran de téléphone.
          const PREFERRED = [720, 480, 360, 1080, 240, 144];
          function pick(items, heightOf) {
            for (const h of PREFERRED) { const it = items.find(i => heightOf(i) === h); if (it) return it; }
            return items[0];
          }
        """

        switch provider {
        case .ytdown:
            return common + """
          (async () => {
            // Page de blocage Cloudflare (limite de débit, IP refusée) : inutile
            // d'attendre, YT1s prend le relais tout de suite.
            if (/access denied|error 10\\d\\d|rate limited/i.test(document.title + ' ' + (document.body ? document.body.innerText.slice(0, 400) : ''))) {
              post({type:'error', message:'blocked by cloudflare'}); return;
            }
            const input = await waitFor(() => document.querySelector('#postUrl'), 30000);
            if (!input) return; // encore sur le défi Cloudflare : la page se rechargera
            // Le formulaire n'est piloté par le site qu'une fois jQuery prêt. Cliquer
            // avant enverrait un vrai POST, la page se rechargerait, et on
            // recommencerait en boucle jusqu'au blocage Cloudflare (erreur 1015).
            await waitFor(() => document.readyState === 'complete' && window.jQuery, 20000);
            await sleep(800);
            post({type:'step', message:'form ready, jq=' + !!window.jQuery});
            input.value = 'https://www.youtube.com/watch?v=' + VIDEO_ID;
            input.dispatchEvent(new Event('input', {bubbles:true}));
            const btn = document.querySelector('#ytdown-downloader-form button[type=submit]');
            if (btn) btn.click();

            post({type:'step', message:'submitted'});
            const select = await waitFor(() => document.querySelector('.download-option'), 30000);
            if (!select) {
              const r = document.querySelector('.jumbotron .result, .result, .alert');
              post({type:'error', message:'no formats: ' + (r ? r.innerText.slice(0, 160) : '')}); return;
            }
            // Musique : la seule option MP3 du site (128 kbit/s). Vidéo : un MP4.
            const wanted = AUDIO ? /^MP3/i : /^MP4/i;
            const files = [...select.options].filter(o => wanted.test(o.text) && /^https?:/.test(o.value));
            if (!files.length) { post({type:'error', message: AUDIO ? 'no mp3' : 'no mp4'}); return; }
            const opt = AUDIO ? files[0]
              : pick(files, o => { const m = o.text.match(/x(\\d{3,4})/); return m ? +m[1] : 0; });

            // Le lien de l'option est un « worker » qu'on interroge jusqu'à ce que
            // la conversion soit terminée : queued → processing 13 %… → completed.
            for (let i = 0; i < 600; i++) {
              let j;
              // Sans cookies : le worker répond `Access-Control-Allow-Origin: *`,
              // que le navigateur refuse dès qu'on envoie des identifiants.
              try { j = await fetch(opt.value).then(r => r.json()); }
              catch(e) { post({type:'step', message:'worker: ' + e}); await sleep(2000); continue; }
              const status = String(j.status || '').toLowerCase();
              const pct = parseFloat(String(j.percent || j.progress || '0'));
              if (!isNaN(pct)) post({type:'progress', value: pct / 100});
              if (status === 'completed' && j.fileUrl) {
                post({type:'result', url: j.fileUrl, name: j.fileName || ''}); return;
              }
              if (status === 'error' || status === 'failed') { post({type:'error', message: status}); return; }
              await sleep(1500);
            }
            post({type:'error', message:'conversion too long'});
          })();
        })();
        """

        case .yt1s:
            return common + """
          // Le widget est une app React : le lien final vit dans son état, sous la
          // forme {status:'tunnel', url, filename}. On le lit dans l'arbre React
          // plutôt que d'intercepter fetch — le widget détecte les fonctions
          // natives remplacées et se bloque (« automated_browser_detected »).
          function findResult() {
            // Remonte depuis chaque bouton : le résultat vit dans un composant parent.
            for (const el of document.querySelectorAll('button')) {
              const key = Object.keys(el).find(k => k.startsWith('__reactFiber'));
              if (!key) continue;
              for (let f = el[key], d = 0; f && d < 14; d++, f = f.return) {
                for (let h = f.memoizedState, n = 0; h && n < 40; n++, h = h.next) {
                  const v = h.memoizedState;
                  if (v && typeof v === 'object' && typeof v.url === 'string' && /^https?:/.test(v.url)
                      && /tunnel|redirect|stream|success/i.test(String(v.status || ''))) return v;
                }
              }
            }
            return null;
          }
          (async () => {
            const tab = await waitFor(() => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === (AUDIO ? 'Audio' : 'Video')), 30000);
            if (!tab) { post({type:'error', message:'widget not loaded'}); return; }
            tab.click();
            await sleep(800);
            // Musique : lignes « 320kbps mp3 », la meilleure d'abord. Vidéo : « 720p mp4 ».
            const rowPattern = AUDIO ? /\\d{2,3}kbps\\s+mp3/i : /\\d{3,4}p/;
            const rows = await waitFor(() => {
              const r = [...document.querySelectorAll('tr')].filter(tr => rowPattern.test(tr.innerText) && /download/i.test(tr.innerText));
              return r.length ? r : null;
            }, 20000);
            if (!rows) { post({type:'error', message:'no formats'}); return; }
            const row = AUDIO
              ? rows.sort((a, b) => (+(b.innerText.match(/(\\d{2,3})kbps/) || [0,0])[1]) - (+(a.innerText.match(/(\\d{2,3})kbps/) || [0,0])[1]))[0]
              : pick(rows, tr => { const m = tr.innerText.match(/(\\d{3,4})p/); return m ? +m[1] : 0; });
            const btn = [...row.querySelectorAll('button')].find(b => /download/i.test(b.textContent)) || row.querySelector('button');
            btn.click();

            // Le widget n'affiche pas de pourcentage : on avance doucement pour
            // montrer que ça travaille.
            let fake = 0;
            for (let i = 0; i < 240; i++) {
              await sleep(500);
              const res = findResult();
              if (res) { post({type:'result', url: res.url, name: res.filename || ''}); return; }
              // Seulement les messages d'échec explicites : le pied de page
              // contient toujours « Report an issue ».
              const failure = document.body.innerText.match(/(something went wrong|video (is )?unavailable|failed to (convert|process|download)|conversion failed)/i);
              if (failure && i > 6) { post({type:'error', message: failure[0]}); return; }
              fake = Math.min(0.9, fake + 0.02);
              post({type:'progress', value: fake});
              // Filet : si l'état reste introuvable, on appuie sur « Download Now »
              // et Swift attrape la navigation vers le fichier.
              if (i > 0 && i % 10 === 0) {
                const now = [...document.querySelectorAll('button, a')].find(b => /download now/i.test(b.textContent));
                if (now) now.click();
              }
            }
            post({type:'error', message:'conversion too long'});
          })();
        })();
        """
        }
    }
}

/// `WKUserContentController` retient fortement ses destinataires : sans ce
/// relais, le résolveur ne serait jamais libéré.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
