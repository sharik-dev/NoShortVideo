//
//  AdBlockService.swift
//  No short video
//

import WebKit

/// Bloqueur de publicité, au niveau du **réseau**.
///
/// Masquer un bandeau en CSS ne fait que cacher une requête déjà partie : la
/// vidéo publicitaire se charge quand même, la régie compte l'impression, et la
/// bande passante est consommée. WebKit sait faire mieux avec
/// `WKContentRuleList` : les règles sont compilées une fois, appliquées par le
/// moteur avant toute requête, et coûtent bien moins cher qu'un
/// MutationObserver côté page.
///
/// Deux familles de règles :
/// - `block` sur les domaines de régies publicitaires ;
/// - `css-display-none` pour les emplacements qui restent, côté Instagram et X.
///
/// ## YouTube en est entièrement exclu — c'est délibéré
///
/// Chaque règle porte `unless-domain` sur `youtube.com` et `youtu.be`, donc
/// **rien n'est bloqué tant que la page affichée est YouTube ou YouTube
/// Music**. Deux raisons, dans cet ordre :
///
/// 1. Ça ne servait à rien. Les annonces de YouTube sont servies par
///    `googlevideo.com`, le domaine qui sert aussi la vidéo et la musique :
///    aucune requête publicitaire séparée à intercepter.
/// 2. Ça se retournait contre nous. Une version précédente bloquait
///    `/pagead/`, `/api/stats/ads` et `/ptracking` sur YouTube — exactement les
///    appels que YouTube surveille pour repérer un bloqueur. Les voir échouer
///    déclenche sa contre-mesure, et des annonces apparaissent là où il n'y en
///    avait pas, YouTube Music compris.
///
/// Les annonces YouTube sont traitées ailleurs, dans le lecteur, par
/// `AdSkipService`. Ici on s'occupe du reste du web.
///
/// Ce qui n'est **jamais** bloqué : `googlevideo.com`, les comptes Google et
/// tout ce qui touche à la connexion. Une règle trop large ne casse pas un
/// bandeau, elle casse la lecture.
enum AdBlockService {

    /// Préférence utilisateur (`SettingsView`). Activé par défaut.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "adBlockEnabled") as? Bool ?? true
    }

    private static let identifier = "nsv-adblock-v2"

    /// La liste compilée, gardée en mémoire pour être ajoutée ou retirée à
    /// chaud des webviews quand l'utilisateur bascule le réglage.
    private(set) static var ruleList: WKContentRuleList?

    /// Une compilation ratée ne se retente pas : `apply` est appelé à chaque
    /// changement de réglage et à chaque fin de chargement, et réessayer en
    /// boucle noierait la console sans jamais donner un résultat différent.
    private static var compileFailed = false

    /// Compile la liste (ou la relit du cache WebKit) puis appelle `completion`
    /// sur la file principale.
    static func prepare(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let ruleList { completion(ruleList); return }
        if compileFailed { completion(nil); return }

        let store = WKContentRuleListStore.default()
        store?.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: rules
        ) { list, error in
            DispatchQueue.main.async {
                if let error {
                    // Une règle invalide ne doit jamais empêcher la navigation :
                    // on continue sans bloqueur.
                    compileFailed = true
                    print("AdBlockService: compilation échouée — \(error.localizedDescription)")
                }
                ruleList = list
                completion(list)
            }
        }
    }

    /// Webviews où la liste est actuellement posée. Sert à ne rien faire quand
    /// l'état demandé est déjà celui en place.
    private static var applied = NSHashTable<WKWebView>.weakObjects()

    /// Applique l'état courant du réglage à une webview déjà construite.
    /// Appelable à chaud : c'est ce qui rend le toggle immédiat.
    ///
    /// **Ne touche à rien si l'état est déjà le bon.** `apply` est appelé sur
    /// chaque `UserDefaults.didChangeNotification` — donc bien plus souvent que
    /// les changements du réglage lui-même. Retirer puis reposer la liste force
    /// WebKit à réévaluer la page entière : fait en boucle pendant un
    /// chargement, ça laissait la webview noire.
    static func apply(to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        let isApplied = applied.contains(webView)

        guard isEnabled else {
            if isApplied, let ruleList {
                controller.remove(ruleList)
                applied.remove(webView)
            }
            return
        }

        guard !isApplied else { return }
        prepare { list in
            guard let list, isEnabled, !applied.contains(webView) else { return }
            controller.add(list)
            applied.add(webView)
        }
    }

    // MARK: - Règles

    /// Format JSON de `WKContentRuleList` : un tableau de
    /// `{ trigger, action }`.
    static let rules: String = """
    [
      { "trigger": { "url-filter": "doubleclick\\\\.net",        "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "googlesyndication\\\\.com",  "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "googleadservices\\\\.com",   "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "adservice\\\\.google",       "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "adnxs\\\\.com",              "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "criteo\\\\.com",             "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "criteo\\\\.net",             "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "taboola\\\\.com",            "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "outbrain\\\\.com",           "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "scorecardresearch\\\\.com",  "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "amazon-adsystem\\\\.com",    "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "moatads\\\\.com",            "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "/pagead/",                "unless-domain": ["*youtube.com", "*youtu.be"] }, "action": { "type": "block" } },

      {
        "trigger": { "url-filter": ".*", "if-domain": ["*instagram.com"] },
        "action": {
          "type": "css-display-none",
          "selector": "[data-ad-preview]"
        }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["*x.com", "*twitter.com"] },
        "action": {
          "type": "css-display-none",
          "selector": "[data-testid='placementTracking']"
        }
      }
    ]
    """
}
